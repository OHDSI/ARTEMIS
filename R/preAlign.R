#' Map concept IDs to concept names
#' Default concept IDs when no file is provided.
default_concept_list <- c(
  905738, 905757, 912105, 912111, 35101858, 35802886, 35802894, 35802896, 35802900, 35802905, 35802919, 35802925, 35802961, 35802969, 35802983, 35802988, 35802990, 35803006, 35803008, 35803023, 35803026, 35803028, 35803029, 35803078, 35803082, 35803165, 35803173, 35803219, 35803257, 35803266, 35803268, 35803298, 35803302, 35803316, 35803318, 35803344, 35803350, 35803376, 37558025, 37561055, 37561338, 42542436, 35100960
)

#' Map concept IDs to concept names
#' Reads a line-delimited list of concept IDs and returns the matching
#' concept names from `regimens_env$concepts` already in scope.
#' @param concept_file Optional path to a file with one concept_id per line.
#' @param ignore_default_list When TRUE and a concept_file is provided, use only
#'   the user-provided list. If no concept_file is provided, the default list is used.
#' @return Character vector of unique concept names.
conceptToList <- function(concept_file = NULL, ignore_default_list = FALSE) {
  if (is.null(concept_file)) {
    if (isTRUE(ignore_default_list)) {
      warning("ignore_default_list = TRUE but no concept_file provided; using default_concept_list instead.")
    }
    selection <- default_concept_list
  } else {
    user_list <- readLines(concept_file, warn = FALSE)
    user_list <- trimws(user_list)
    user_list <- user_list[nzchar(user_list)]
    if (isTRUE(ignore_default_list)) {
      selection <- user_list
    } else {
      selection <- unique(c(default_concept_list, user_list))
    }
  }
  selection <- suppressWarnings(as.integer(selection))
  if (any(is.na(selection))) {
    stop("All concept IDs must be integers.")
  }
  if (!exists("regimens_env")) {
    stop("`regimens_env` not found in scope")
  }
  if (is.null(regimens_env$concepts)) {
    stop("`regimens_env$concepts` not found in scope")
  }
  df <- regimens_env$concepts
  name_col <- if ("concept_name" %in% names(df)) "concept_name" else "name"
  names_out <- unique(df[[name_col]][df$concept_id %in% selection])
  names_out
}

#' Normalize text for blacklist matching
#' Strips punctuation, trims whitespace, and lowercases text.
#' @param text Character vector to normalize.
#' @return Character vector of normalized text.
cleanText <- function(text) {
  normalized <- gsub("[^A-Za-z]+", " ", as.character(text))
  normalized <- trimws(normalized)
  normalized <- gsub("\\s+", " ", normalized)
  tolower(normalized)
}

#' Escape regex metacharacters
#' @param text Character vector to escape.
#' @return Character vector with regex metacharacters escaped.
escapeRegex <- function(text) {
  gsub("([\\\\.^$|()\\[\\]{}*+?])", "\\\\\\1", text, perl = TRUE)
}

#' Build a single regex from blacklist terms
#'
#' @param blacklist_set Character vector of blacklist terms.
#' @return Regex pattern string.
buildBlacklistRegex <- function(blacklist_set) {
  cleaned <- vapply(blacklist_set, cleanText, character(1))
  escaped <- escapeRegex(cleaned)
  paste0("\\b(", paste(escaped, collapse = "|"), ")\\b")
}

#' Detect blacklist matches across any column (case-insensitive)
#' Expands multi-word terms by adding whitespace-stripped variants 
#' before regex matching, while keeping original terms intact.
#' @param frame Data frame to check.
#' @param blacklist_set Character vector of blacklist terms.
#' @return Logical vector, TRUE for rows containing any blacklist term.
rowHasBlacklist <- function(frame, blacklist_set) {
  if (length(blacklist_set) == 0) {
    return(rep(FALSE, nrow(frame)))
  }
  extra_terms <- character(0)
  for (term in blacklist_set) {
    if (grepl("\\s", term)) {
      extra_terms <- c(extra_terms, gsub("\\s+", "", term))
    }
  }
  if (length(extra_terms) > 0) {
    blacklist_set <- unique(c(blacklist_set, extra_terms))
  }
  pattern <- buildBlacklistRegex(blacklist_set)
  cols <- intersect(c("regName", "shortString"), names(frame))
  if (length(cols) == 0) {
    stop("Expected regName or shortString columns for blacklist matching")
  }
  cleaned_df <- as.data.frame(lapply(frame[cols], function(col) cleanText(col)),
                              stringsAsFactors = FALSE)
  apply(cleaned_df, 1, function(row_vals) any(grepl(pattern, row_vals, perl = TRUE)))
}

#' Run blacklist cleaning pipeline on in-scope regimens_env
#' Uses `regimens_env$regimens` from the current scope, filters rows where any
#' cell contains a blacklist term (case-insensitive), updates
#' `regimens_env$regimens` in place.
#' @param concept_file Optional path to a file with one concept_id per line.
#' @param ignore_default_list When TRUE and a concept_file is provided, use only
#'   the user-provided list. If no concept_file is provided, the default list is used.
#' @return Invisible cleaned data frame.
#' @export
cleanByBlacklist <- function(concept_file = NULL,
                             ignore_default_list = FALSE) {
  if (!exists("regimens_env")) {
    stop("`regimens_env` not found in scope")
  }
  if (is.null(regimens_env$regimens)) {
    stop("`regimens_env$regimens` not found in scope")
  }
  frame <- regimens_env$regimens
  blacklist_set <- conceptToList(concept_file, ignore_default_list)

  is_blacklisted <- rowHasBlacklist(frame, blacklist_set)
  n_drop <- sum(is_blacklisted)

  frame <- frame[!is_blacklisted, , drop = FALSE]

  regimens_env$regimens <- frame
  invisible(frame)
}
