#!/usr/bin/env Rscript
# Author: Naveen Duhan
# SPDX-License-Identifier: MIT
# Description: Runs VirFinder 8-mer viral scoring on assembled contigs, handles empty FASTA inputs safely, computes FDR q-values and 3-mer Shannon entropy metrics, and writes full and filtered TSV outputs.

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
seq_names <- sub("^>\\s*(\\S+).*$", "\\1", lines[header_idx], perl = TRUE)
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

get_script_dir <- function() {
  cmd_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", cmd_args, value = TRUE)
  if (length(file_arg) > 0) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[1]), mustWork = FALSE)))
  }
  getwd()
}

ensure_compiler_env <- function() {
  env_bin <- normalizePath(file.path(R.home(), "..", "..", "bin"), mustWork = FALSE)
  if (dir.exists(env_bin)) {
    cur_path <- Sys.getenv("PATH", "")
    path_sep <- .Platform$path.sep
    parts <- strsplit(cur_path, path_sep, fixed = TRUE)[[1]]
    if (!(env_bin %in% parts)) {
      Sys.setenv(PATH = paste(c(env_bin, parts), collapse = path_sep))
    }
  }
  if (!identical(Sys.info()[["sysname"]], "Darwin")) return(invisible(NULL))
  cur_sdk <- Sys.getenv("SDKROOT", "")
  if (nzchar(cur_sdk) && dir.exists(cur_sdk)) return(invisible(NULL))
  sdk <- tryCatch(
    trimws(system2("xcrun", "--show-sdk-path", stdout = TRUE, stderr = FALSE)[1]),
    error = function(e) ""
  )
  if (!nzchar(sdk) || !dir.exists(sdk)) {
    candidates <- c(
      "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk",
      "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    )
    hit <- candidates[dir.exists(candidates)]
    if (length(hit) > 0) sdk <- hit[1]
  }
  if (nzchar(sdk) && dir.exists(sdk)) {
    Sys.setenv(SDKROOT = sdk, CONDA_BUILD_SYSROOT = sdk)
  }
  invisible(NULL)
}

ensure_virfinder <- function() {
  if (requireNamespace("VirFinder", quietly = TRUE)) return(invisible(TRUE))

  r_ver <- paste0(R.version$major, ".", strsplit(R.version$minor, "\\.")[[1]][1])
  plat <- gsub("[^A-Za-z0-9._-]", "_", R.version$platform)
  base_cache <- file.path(Sys.getenv("HOME", tempdir()), ".metanextviro", "r_libs")
  ok_dir <- dir.create(base_cache, recursive = TRUE, showWarnings = FALSE) || dir.exists(base_cache)
  if (!ok_dir || file.access(base_cache, 2) != 0) {
    base_cache <- file.path(tempdir(), "metanextviro_r_libs")
    dir.create(base_cache, recursive = TRUE, showWarnings = FALSE)
  }
  user_lib <- file.path(base_cache, paste0(plat, "-R", r_ver))
  dir.create(user_lib, recursive = TRUE, showWarnings = FALSE)
  .libPaths(c(user_lib, .libPaths()))
  if (requireNamespace("VirFinder", lib.loc = user_lib, quietly = TRUE)) return(invisible(TRUE))

  lock_dir <- file.path(base_cache, paste0("virfinder_", plat, "_R", r_ver, ".lock"))
  waited <- 0L
  while (!dir.create(lock_dir, showWarnings = FALSE)) {
    Sys.sleep(2)
    waited <- waited + 2L
    if (requireNamespace("VirFinder", lib.loc = user_lib, quietly = TRUE)) return(invisible(TRUE))
    if (waited >= 180L) unlink(lock_dir, recursive = TRUE)
  }
  on.exit(unlink(lock_dir, recursive = TRUE), add = TRUE)

  if (!requireNamespace("VirFinder", lib.loc = user_lib, quietly = TRUE)) {
    ensure_compiler_env()
    vendored <- file.path(get_script_dir(), "vendor", "VirFinder_1.1.tar.gz")
    tarball <- if (file.exists(vendored) && file.info(vendored)$size > 0) {
      vendored
    } else {
      dl <- file.path(base_cache, "VirFinder_1.1.tar.gz")
      if (!file.exists(dl) || file.info(dl)$size == 0) {
        url <- "https://raw.githubusercontent.com/jessieren/VirFinder/master/linux/VirFinder_1.1.tar.gz"
        message("Downloading VirFinder 1.1 source package...")
        utils::download.file(url, destfile = dl, mode = "wb", quiet = TRUE)
      }
      dl
    }
    message("Compiling VirFinder 1.1 for ", plat, " (R ", r_ver, ") into ", user_lib, " ...")
    utils::install.packages(tarball, lib = user_lib, repos = NULL, type = "source", quiet = FALSE)
  }
  if (!requireNamespace("VirFinder", quietly = TRUE)) {
    stop("Failed to load or install VirFinder 1.1 in ", user_lib)
  }
  invisible(TRUE)
}

ensure_virfinder()
suppressPackageStartupMessages(library(VirFinder))
result <- VF.pred(input_file)
result$name <- sub("^\\s*(\\S+).*$", "\\1", as.character(result$name), perl = TRUE)
qc_df <- qc_df[!duplicated(qc_df$seq_id), , drop = FALSE]

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
