# ==============================================================================
# 1. Core Engine: AutoCellType
# ==============================================================================

#' @title AutoCellType
#' @description
#' A high-precision, parallelized single-cell annotation engine.
#'
#' @param input **Required**. The input marker data. Supports two formats:
#'   \itemize{
#'     \item \strong{Data Frame}: Output from Seurat's \code{FindAllMarkers()}. Must contain \code{cluster} and \code{gene} (or rownames) columns, plus \code{avg_log2FC} (or \code{avg_logFC}).
#'     \item \strong{List}: A named list of marker vectors, e.g., \code{list("Cluster0" = c("GeneA", "GeneB"), ...)}.
#'   }
#' @param tissuename **Character**. The tissue of origin (e.g., "Human Liver", "Mouse Brain"). Serves as the primary biological context.
#' @param n_cores **Integer**. Number of parallel threads.
#'   \itemize{
#'     \item \code{1} (Default): Sequential processing (safest for debugging).
#'     \item \code{>1}: Parallel processing (Recommended: 4-8). Requires high API rate limits.
#'   }
#' @param cell_ontology **Constraint Mode**. Controls the standardization of the 'primary_lineage' field:
#'   \itemize{
#'     \item \code{NULL} (Default): Uses the built-in **Universal Ontology** (~40 types).
#'     \item \code{Character Vector}: **Recommended for Sub-clustering**. A user-defined list of allowed subtypes.
#'   }
#' @param prior_info **Character** (Optional). External biological context. E.g., "T cell sub-clustering".
#' @param model **Character**. LLM model name. Default \code{"gpt-4o-mini"}. \code{"gpt-4o"} is recommended for sub-clustering.
#' @param topgenenumber **Integer**. The number of top markers (sorted by LogFC) to send per cluster. Default: 20.
#' @param p_val_thresh **Numeric**. Significance threshold. Default: 0.05.
#' @param base_url **Character**. API endpoint. Default: "https://api.gpt.ge/v1".
#' @param api_key **Character**. OpenAI-compatible API Key. Defaults to \code{Sys.getenv("OPENAI_API_KEY")}.
#' @param retries **Integer**. Max retry attempts per cluster. Default: 3.
#' @param verbose **Logical**. Print progress bar. Default: \code{TRUE}.
#'
#' @return A \code{tibble} containing standardized columns: \code{cluster_id}, \code{primary_lineage}, \code{detailed_subtype}, \code{functional_state}, \code{confidence}, \code{reasoning}.
#'
#' @examples
#' \dontrun{
#'   # =========================================================================
#'   # Example 1: Standard Annotation (Sequential)
#'   # =========================================================================
#'   library(dplyr)
#'
#'   # 1. Create Mock Seurat Output
#'   # Cluster 0: T cells (CD3D, CD8A)
#'   # Cluster 1: B cells (MS4A1, CD79A)
#'   # Cluster 2: Fibroblasts (COL1A1, DCN)
#'   mock_markers <- data.frame(
#'     cluster = c(rep("0", 3), rep("1", 3), rep("2", 3)),
#'     gene = c("CD3D", "CD8A", "GZMK",      # C0
#'              "MS4A1", "CD79A", "CD19",    # C1
#'              "COL1A1", "DCN", "PDGFRA"),  # C2
#'     avg_log2FC = c(2.5, 2.3, 1.8, 2.4, 2.2, 2.0, 3.1, 2.8, 2.5),
#'     p_val_adj = rep(0.001, 9)
#'   )
#'
#'   # 2. Run
#'   res <- AutoCellType(
#'     input = mock_markers,
#'     tissuename = "Human PBMC",
#'     n_cores = 1, # Sequential
#'     api_key = "sk-..."
#'   )
#'   print(res)
#'
#'   # =========================================================================
#'   # Example 2: High-Performance Parallel Mode
#'   # =========================================================================
#'   # If you have 20+ clusters, use n_cores = 4 or 8 to speed up by 4x-8x.
#'
#'   res_parallel <- AutoCellType(
#'     input = mock_markers,
#'     tissuename = "Human Tissue",
#'     n_cores = 4, # Use 4 threads
#'     model = "gpt-4o-mini",
#'     api_key = "sk-..."
#'   )
#'
#'   # =========================================================================
#'   # Example 3: Sub-clustering (Custom Ontology + Context)
#'   # =========================================================================
#'   # Scenario: You have re-clustered T cells and need to distinguish subtypes.
#'
#'   t_ontology <- c("CD8 Naive", "CD8 Effector", "CD8 Exhausted", "Treg")
#'
#'   res_sub <- AutoCellType(
#'     input = mock_markers, # Assume these are T cell sub-clusters
#'     tissuename = "Human Liver",
#'     prior_info = "Sub-clustering of CD3+ T cells.", # Inject context
#'     cell_ontology = t_ontology, # Enforce specific names
#'     model = "gpt-4o", # Better model for subtle differences
#'     n_cores = 4
#'   )
#' }
#' @export
AutoCellType <- function(
    input,
    tissuename,
    cell_ontology = NULL,
    prior_info = NULL,
    n_cores = 1,
    model = "gpt-4o-mini",
    topgenenumber = 20,
    p_val_thresh = 0.05,
    base_url = "https://api.gpt.ge/v1",
    api_key = NULL,
    retries = 3,
    verbose = TRUE
) {

  # --- 1. Configuration ---
  STANDARD_COLS <- c("cluster_id", "primary_lineage", "detailed_subtype", "functional_state", "confidence", "reasoning")

  default_ontology <- c(
    "T cell", "B cell", "Plasma cell", "NK cell", "Myeloid cell", "Macrophage", "Monocyte",
    "Dendritic cell", "Neutrophil", "Mast cell", "Eosinophil", "Basophil",
    "Fibroblast", "Mesenchymal cell", "Smooth muscle cell", "Pericyte", "Adipocyte",
    "Mesothelial cell", "Chondrocyte", "Osteoblast", "Stromal cell",
    "Epithelial cell", "Endothelial cell", "Lymphatic endothelial cell", "Keratinocyte",
    "Hepatocyte", "Cholangiocyte", "Pneumocyte", "Podocyte", "Mesangial cell",
    "Neuron", "Glial cell", "Schwann cell", "Cardiomyocyte",
    "Stem cell", "Progenitor cell", "Embryonic stem cell", "Trophoblast",
    "Germ cell", "Erythrocyte", "Platelet", "Melanocyte"
  )
  current_ontology <- if (is.character(cell_ontology)) cell_ontology else default_ontology
  should_enforce <- !isFALSE(cell_ontology)

  # --- 2. Dependencies ---
  check_deps <- function() {
    pkgs <- c("openai", "dplyr", "glue", "tibble", "jsonlite", "stringr", "future", "future.apply", "progressr")
    missing <- pkgs[!sapply(pkgs, requireNamespace, quietly = TRUE)]
    if (length(missing) > 0) stop("Missing packages: ", paste(missing, collapse = ", "))
  }

  # --- 3. Data Formatting ---
  format_markers <- function(dat, n, p_thresh) {
    if (inherits(dat, "data.frame")) {
      cols <- colnames(dat)
      if (!"gene" %in% cols) {
        if ("feature" %in% cols) dat <- dplyr::rename(dat, gene = feature)
        else dat$gene <- rownames(dat)
      }
      if (!"avg_log2FC" %in% cols && "avg_logFC" %in% cols) dat <- dplyr::rename(dat, avg_log2FC = avg_logFC)

      dat$avg_log2FC <- as.numeric(dat$avg_log2FC)
      if("p_val_adj" %in% cols) dat$p_val_adj <- as.numeric(dat$p_val_adj)

      dat |>
        dplyr::filter(if("p_val_adj" %in% colnames(dat)) p_val_adj < p_thresh else TRUE) |>
        dplyr::filter(avg_log2FC > 0) |>
        dplyr::group_by(cluster) |>
        dplyr::slice_max(order_by = avg_log2FC, n = n) |>
        dplyr::summarise(genes = paste0(gene, collapse = ", "), .groups = "drop") |>
        dplyr::mutate(cluster = as.character(cluster)) |>
        tibble::deframe()
    } else if (inherits(dat, "list")) {
      sapply(dat, function(x) paste0(head(x, n), collapse = ", "))
    } else stop("Input format error: Must be data.frame or list")
  }

  # --- 4. Prompt Engineering ---
  make_system_prompt <- function() {
    ctx <- glue::glue("Tissue: {tissuename}")
    if (!is.null(prior_info)) ctx <- paste(ctx, glue::glue("Context: {prior_info}"), sep = "\n")

    ontology_str <- if(should_enforce) paste(paste0("- ", current_ontology), collapse = "\n") else "No strict list."
    instruction <- if(should_enforce) glue::glue("Primary Lineage MUST match one of:\n{ontology_str}") else "Use standard names."

    glue::glue("
      Act as a Senior Cell Biologist. Annotate the provided single-cell cluster.
      {ctx}
      {instruction}

      RULES:
      1. 'detailed_subtype' is MANDATORY. If unsure, copy primary_lineage.
      2. NO MARKDOWN. NO EXPLANATIONS OUTSIDE JSON.
      3. Output a SINGLE JSON object.

      FORMAT:
      {{
        \"cluster_id\": \"id\",
        \"primary_lineage\": \"Standard Name\",
        \"detailed_subtype\": \"Specific Subtype\",
        \"functional_state\": \"State\",
        \"confidence\": \"High/Medium/Low\",
        \"reasoning\": \"Short logic\"
      }}
    ")
  }

  # --- 5. JSON Repair Helper ---
  repair_json <- function(json_str) {
    # 1. Clean markdown
    json_str <- gsub("```json", "", json_str)
    json_str <- gsub("```", "", json_str)
    json_str <- trimws(json_str)

    # 2. Try clean parse
    out <- tryCatch(jsonlite::fromJSON(json_str), error = function(e) NULL)
    if (!is.null(out)) return(out)

    # 3. Aggressive Repair (Fix Premature EOF)
    if (!grepl("\\}$", json_str)) {
      # Try appending '}'
      try1 <- paste0(json_str, "}")
      out <- tryCatch(jsonlite::fromJSON(try1), error = function(e) NULL)
      if (!is.null(out)) return(out)

      # Try appending '"}' (in case value was cut off)
      try2 <- paste0(json_str, "\"}")
      out <- tryCatch(jsonlite::fromJSON(try2), error = function(e) NULL)
      if (!is.null(out)) return(out)
    }

    return(NULL)
  }

  # --- 6. Single Cluster Runner (Fault Tolerant) ---
  run_single_cluster <- function(cid, cgenes, client, sys_prompt, retry_limit) {
    user_msg <- glue::glue("Cluster ID: {cid}\nMarkers: {cgenes}")
    last_error <- "Unknown"

    for (i in 1:retry_limit) {
      if (i > 1) Sys.sleep(2^(i-1))

      # API Call
      api_res <- tryCatch({
        client$chat$completions$create(
          model = model,
          messages = list(list(role = "system", content = sys_prompt), list(role = "user", content = user_msg)),
          temperature = 0.1, max_tokens = 2000, response_format = list(type = "json_object")
        )
      }, error = function(e) {
        # [FATAL ERROR CHECK]
        # If error is 400 (Bad Request) or "model does not exist", STOP immediately.
        if (grepl("400", e$message) || grepl("does not exist", e$message)) {
          stop(paste("FATAL_API_ERROR:", e$message))
        }
        return(list(error = e$message))
      })

      # Handle Fatal Error thrown above
      if (inherits(api_res, "error")) {
        stop(api_res$message) # Re-throw to be caught by wrapper
      }

      if (!is.null(api_res$error)) {
        last_error <- paste("API Error:", api_res$error)
        next
      }

      # Parse & Repair
      raw <- api_res$choices[[1]]$message$content
      # Extract JSON-like part
      json_match <- stringr::str_extract(raw, "(?s)\\{.*")
      target <- if (!is.na(json_match)) json_match else raw

      df <- repair_json(target)

      if (is.null(df)) {
        last_error <- paste("JSON Parse Failed. Raw:", substr(raw, 1, 50))
        next
      }

      # Standardization
      if (is.list(df) && !is.data.frame(df)) df <- dplyr::bind_rows(df)
      colnames(df) <- tolower(colnames(df))

      missing <- setdiff(STANDARD_COLS, colnames(df))
      if (length(missing) > 0) for (col in missing) df[[col]] <- NA

      # [Gap Filling] Force 'detailed_subtype' if NA
      if ("detailed_subtype" %in% colnames(df)) {
        val <- df$detailed_subtype
        if (is.na(val) || val == "" || val == "N/A" || val == "None" || val == "NA") {
          # Fallback to primary lineage
          df$detailed_subtype <- if("primary_lineage" %in% colnames(df)) df$primary_lineage else "Unknown"
        }
      }

      # Ontology Alignment
      if (should_enforce && "primary_lineage" %in% colnames(df)) {
        val <- df$primary_lineage[1]
        if (!is.na(val) && !val %in% current_ontology) {
          idx <- match(gsub("s$", "", tolower(val)), gsub("s$", "", tolower(current_ontology)))
          if (!is.na(idx)) df$primary_lineage <- current_ontology[idx]
        }
      }

      df$cluster_id <- as.character(cid)
      return(df[, STANDARD_COLS, drop = FALSE])
    }

    # Return Failed Row
    return(tibble::tibble(
      cluster_id = as.character(cid),
      primary_lineage = "Failed",
      detailed_subtype = last_error,
      functional_state = NA, confidence = "None", reasoning = NA
    ))
  }

  # --- 7. Main Loop ---
  tryCatch({
    check_deps()
    key <- if (is.null(api_key)) Sys.getenv("OPENAI_API_KEY") else api_key
    client <- openai::OpenAI(api_key = key, base_url = base_url)

    markers_vec <- format_markers(input, topgenenumber, p_val_thresh)
    if (length(markers_vec) == 0) stop("No valid markers.")

    sys_prompt <- make_system_prompt()
    cluster_ids <- names(markers_vec)

    if (verbose) message(glue::glue("=== AutoCellType ({model}) | {length(cluster_ids)} Clusters | Cores: {n_cores} ==="))

    worker <- function(cid) run_single_cluster(cid, markers_vec[cid], client, sys_prompt, retries)

    if (n_cores > 1) {
      future::plan(future::multisession, workers = n_cores)
      res_list <- progressr::with_progress({
        p <- progressr::progressor(steps = length(cluster_ids))
        future.apply::future_lapply(cluster_ids, function(cid) {
          p(sprintf("Cluster %s", cid))
          worker(cid)
        }, future.seed = TRUE)
      })
    } else {
      res_list <- purrr::map(cluster_ids, function(cid) {
        if(verbose) message(glue::glue("Processing Cluster {cid}..."))
        worker(cid)
      })
    }

    final_df <- dplyr::bind_rows(res_list) |> dplyr::as_tibble()
    if (verbose) message("=== Done ===")
    return(final_df)

  }, error = function(e) stop("AutoCellType Critical Error: ", e$message))
}


