#!/usr/bin/env Rscript
# Enhanced VirFinder wrapper with empty-FASTA handling, FDR q-values,
# 3-mer Shannon entropy repeat screening, and descending score sorting.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3) {
  stop("Usage: Rscript run_virfinder.R <input_fasta> <full_tsv> <filtered_tsv> [min_score] [max_qvalue] [moderate_score]")
}

input_file <- args[1]
output_file <- args[2]
filtered_file <- args[3]
min_score <- if (length(args) >= 4) as.numeric(args[4]) else 0.9
max_qvalue <- if (length(args) >= 5) as.numeric(args[5]) else 0.05
moderate_score <- if (length(args) >= 6) as.numeric(args[6]) else 0.7

cols <- c("name", "length", "score", "pvalue", "qvalue",
          "gc_percent", "n_fraction", "kmer_entropy",
          "low_complexity_flag", "confidence_tier")

write_empty_outputs <- function() {
  empty_df <- as.data.frame(setNames(replicate(length(cols), character(0), simplify = FALSE), cols))
  write.table(empty_df, file = output_file, sep = "\t", quote = FALSE, row.names = FALSE)
  write.table(empty_df, file = filtered_file, sep = "\t", quote = FALSE, row.names = FALSE)
}

if (!file.exists(input_file) || file.info(input_file)$size == 0) {
  message("No candidate contigs to score in VirFinder; writing header-only tables.")
  write_empty_outputs()
  quit(save = "no", status = 0)
}

lines <- readLines(input_file, warn = FALSE)
header_idx <- which(substr(lines, 1, 1) == ">")
if (length(header_idx) == 0) {
  message("Input FASTA contains zero sequences; writing header-only tables.")
  write_empty_outputs()
  quit(save = "no", status = 0)
}

# Compute sequence QC metrics (GC%, N-fraction, normalized 3-mer entropy) per contig
seq_names <- sub("^>\\s*([^\\s]+).*$", "\\1", lines[header_idx])
end_idx <- c(header_idx[-1] - 1, length(lines))

calc_seq_qc <- function(seq_str) {
  s <- toupper(seq_str)
  n_len <- nchar(s)
  if (n_len == 0) return(c(0, 0, 0))
  chars <- strsplit(s, "", fixed = TRUE)[[1]]
  n_cnt <- sum(chars == "N")
  gc_cnt <- sum(chars == "G" | chars == "C")
  valid <- max(1, n_len - n_cnt)
  gc_pct <- round(100.0 * gc_cnt / valid, 2)
  n_frac <- round(n_cnt / n_len, 4)
  if (n_len < 3) return(c(gc_pct, n_frac, 0))
  kmers <- substring(s, 1:(n_len - 2), 3:n_len)
  kmers <- kmers[grepl("^[ACGT]{3}$", kmers)]
  if (length(kmers) == 0) return(c(gc_pct, n_frac, 0))
  probs <- as.numeric(table(kmers)) / length(kmers)
  ent <- round(-sum(probs * log2(probs)) / 6.0, 4)
  c(gc_pct, n_frac, ent)
}

qc_mat <- t(vapply(seq_along(header_idx), function(i) {
  if (header_idx[i] + 1 <= end_idx[i]) {
    s <- paste(lines[(header_idx[i] + 1):end_idx[i]], collapse = "")
  } else {
    s <- ""
  }
  calc_seq_qc(s)
}, numeric(3)))
qc_df <- data.frame(
  seq_id = seq_names,
  gc_percent = qc_mat[, 1],
  n_fraction = qc_mat[, 2],
  kmer_entropy = qc_mat[, 3],
  stringsAsFactors = FALSE
)

suppressPackageStartupMessages(library(VirFinder))
result <- VF.pred(input_file)
result$name <- sub("^\\s*([^\\s]+).*$", "\\1", as.character(result$name))

# Compute FDR q-values safely (VF.qvalue spline fails on small N; fallback to BH)
result$qvalue <- tryCatch({
  qv <- VF.qvalue(result$pvalue)
  if (any(is.na(qv)) || length(qv) != nrow(result)) stop("invalid VF.qvalue")
  qv
}, error = function(e) {
  p.adjust(result$pvalue, method = "BH")
})

merged <- merge(result, qc_df, by.x = "name", by.y = "seq_id", all.x = TRUE, sort = FALSE)
merged$low_complexity_flag <- ifelse(
  is.na(merged$kmer_entropy) | merged$kmer_entropy < 0.65 | merged$n_fraction > 0.10,
  "yes", "no"
)

merged$confidence_tier <- ifelse(
  merged$low_complexity_flag == "yes", "low_complexity_suspect",
  ifelse(
    merged$score >= min_score & (merged$qvalue <= max_qvalue | merged$pvalue <= 0.01),
    "high_confidence",
    ifelse(
      merged$score >= moderate_score & merged$pvalue <= 0.05,
      "moderate_confidence",
      "unlikely_viral"
    )
  )
)

merged <- merged[order(-merged$score, merged$qvalue, merged$pvalue, -merged$length, merged$name), cols]
write.table(merged, file = output_file, sep = "\t", quote = FALSE, row.names = FALSE)

filtered <- subset(merged, confidence_tier %in% c("high_confidence", "moderate_confidence"))
write.table(filtered, file = filtered_file, sep = "\t", quote = FALSE, row.names = FALSE)
