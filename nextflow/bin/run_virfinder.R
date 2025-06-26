# Load VirFinder
library(VirFinder)

# Read input arguments
args <- commandArgs(trailingOnly = TRUE)
input_file <- args[1]        # Input FASTA
output_file <- args[2]       # Output full result
filtered_file <- args[3]     # Filtered high-confidence result

# Run VirFinder
result <- VF.pred(input_file)

# Save full results
write.table(result, file = output_file, sep = "\t", quote = FALSE, row.names = FALSE)

# Apply filtering: score ≥ 0.9 and p-value ≤ 0.05
filtered <- subset(result, score >= 0.9 & pvalue <= 0.05)

# Save filtered results
write.table(filtered, file = filtered_file, sep = "\t", quote = FALSE, row.names = FALSE)