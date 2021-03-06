library(dplyr)
library(purrr)
library(reshape2)
library(ggplot2)
library(limma)

library(tibble)
library(dplyr)

source('./granatum_sdk.R')

selected_norm <- gn_get_arg('normalizationMethod')
in_assay <- gn_get_import('assay')

expr_matrix <- in_assay$matrix



# Run selected normalization method
# "Quantile_normalization",
# "Rescale_to_geometric_mean",
# "Size-factor_normalization",
# "Voom"
quantile_normalization <- function(counts) {
  # limma
  norm_mat <- normalizeQuantiles(log(counts+1), ties = F)
  norm_mat
}

deseq_sizefactor_normalization <- function(counts) {
  relative_factors <- (1 / apply(counts, 1, function(x){x %>% {log(.+1)} %>% mean %>% {exp(.)-1}})) %>% map_if( ~ . == Inf, ~ 0) %>% (purrr::simplify)
  relative_counts <- counts * relative_factors

  size_factors <- apply(relative_counts, 2, function(x) median(x[x > 0]))
  norm_counts <- t(t(counts) / size_factors)
  log(norm_counts + 1)
}

scalecenter_normalization <- function(counts) {
  raw_mat <- counts
  raw_mat_l <- log(raw_mat+1)
  means <- exp(apply(raw_mat_l, 2, function(x) mean(x[x > 0]))) - 1
  raw_mat <- sweep(raw_mat, 2, means / mean(means), '/')
  raw_mat_l <- log(raw_mat + 1)

  # repeat
  raw_mat <- exp(raw_mat_l) - 1
  means <- exp(apply(raw_mat_l, 2, function(x) mean(x[x > 0]))) - 1
  raw_mat <- sweep(raw_mat, 2, means / mean(means), '/')
  raw_mat_l <- log(raw_mat + 1)
  raw_mat_l
}

voom_normalization <- function(counts) {
    # E: numeric matrix of normalized expression values on the log2 scale
  norm_mat <- counts %>% voom(normalize.method = 'quantile') %>% .$E %>% {
    . - min(.)
  }
  norm_mat
}

out_mat <- NULL
if (selected_norm == "Quantile_normalization") {
  out_mat <- quantile_normalization(expr_matrix)
} else if (selected_norm == "Rescale_to_geometric_mean") {
  out_mat <- scalecenter_normalization(expr_matrix)
} else if (selected_norm == "Size-factor_normalization") {
  out_mat <- deseq_sizefactor_normalization(expr_matrix)
} else if (selected_norm == "Voom") {
  out_mat <- voom_normalization(expr_matrix)
} else {
  stop(paste0('The selected_norm (', selected_norm, ') is not recognized.', collapse=''))
}

in_assay$matrix <- out_mat

gn_export_statically(in_assay, 'normalizedAssay')

gn_add_result(selected_norm, 'text', list(label='Normalization method', description='Method selected to normalize the assay.'))

# Create plot and encode
create_ggplot <- function(norm_mat) {
  sampling <- NULL
  if (ncol(norm_mat) > 96) {
    sampling <- sample(1:ncol(norm_mat), 96) %>% sort
  } else {
    sampling <- 1:ncol(norm_mat)
  }

  ggdat <- norm_mat[,sampling] %>%
    melt(c('gene', 'sample'), value.name = 'log_expr') %>%
    mutate(sample=factor(sample)) %>%
    filter(log_expr > 0)

  ggdat_gmean <- ggdat %>%
    group_by(sample) %>%
    summarize(gmean = mean(log_expr))
  ggp <-
    ggplot(ggdat) + geom_boxplot(aes(sample, log_expr)) +
    geom_point(
      aes(sample, gmean),
      data = ggdat_gmean,
      color = 'red',
      alpha = 0.5
    ) +
    labs(x = 'Sample', y = 'Log Expr. Lvl. (non-zero)') +
    # theme(axis.text.x = element_text(angle = 90))
    theme(axis.text.x = element_blank())
  ggp
}
out_mat_ggp <- create_ggplot(out_mat)

gn_add_ggplot_to_results(out_mat_ggp, 'Normalized expression values for a random subset of samples are shown as box plots in black and as mean value dots in red.', height=400, dpi=100)
gn_commit()
