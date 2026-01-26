# ==============================================================================
# 2. Wrapper: RunMultipleAnnotations (v2.1 Robust)
# ==============================================================================

#' @title Run Annotation with Multiple Models
#' @description
#' Wrapper to run `AutoCellType` using multiple models.
#' Gracefully handles fatal model errors (e.g. 400 Bad Request) without stopping the whole process.
#'
#' @inheritParams AutoCellType
#' @param models Character vector of model names.
#' @return A combined tibble.
#' @export
RunMultipleAnnotations <- function(input, models = c("gpt-4o", "gpt-4o-mini"), ...) {

  if (length(models) == 0) stop("No models specified.")

  results_list <- list()

  for (m in models) {
    message(glue::glue("\n>>> [RunMultipleAnnotations] Launching: {m} <<<"))

    # Try-catch block specifically for each model run
    res <- tryCatch({
      # Pass ... to AutoCellType
      AutoCellType(input = input, model = m, ...)
    }, error = function(e) {
      # Catch the FATAL ERROR thrown by AutoCellType
      warning(glue::glue("Model '{m}' failed: {e$message}"))

      # Return a placeholder row so we know which model failed
      return(tibble::tibble(
        cluster_id = "Error",
        primary_lineage = "Model Failed",
        detailed_subtype = paste("Error:", e$message),
        model = m,
        timestamp = Sys.time()
      ))
    })

    if (!is.null(res) && nrow(res) > 0) {
      if (!"model" %in% colnames(res)) res$model <- m
      if (!"timestamp" %in% colnames(res)) res$timestamp <- Sys.time()
      results_list[[m]] <- res
    }
  }

  if (length(results_list) == 0) stop("All models failed.")

  combined_results <- dplyr::bind_rows(results_list)

  # Clean up and sort
  if ("cluster_id" %in% colnames(combined_results)) {
    # Helper to sort numeric strings properly (0, 1, 10, 2 -> 0, 1, 2, 10)
    suppressWarnings({
      combined_results <- combined_results |>
        dplyr::mutate(sort_id = as.numeric(cluster_id)) |>
        dplyr::arrange(sort_id, model) |>
        dplyr::select(-sort_id)
    })
  }

  message(glue::glue("\n=== Consensus Annotation Completed. Rows: {nrow(combined_results)} ==="))
  return(combined_results)
}


# ==============================================================================
# 3. Metrics: AssessModelConsensus (v1.0)
# ==============================================================================
#' @title Assess Model Consensus (Expert Arbiter v8.2)
#' @description
#' Uses an LLM to arbitrate conflicts. Added strict type-casting to prevent
#' bind_rows errors between numeric and character IDs.
#'
#' @param results_df RunMultipleAnnotations 的输出
#' @param arbiter_model 建议用最强的模型，如 "gpt-4o"
#' @export
AssessModelConsensus <- function(
    results_df,
    arbiter_model = "gpt-4o",
    api_key = NULL,
    base_url = "https://api.gpt.ge/v1"
) {

  suppressPackageStartupMessages({
    library(dplyr)
    library(openai)
    library(jsonlite)
    library(purrr)
  })

  key <- if (is.null(api_key)) Sys.getenv("OPENAI_API_KEY") else api_key
  client <- openai::OpenAI(api_key = key, base_url = base_url)

  # 1. 数据清洗：过滤失败行
  valid_df <- results_df |>
    dplyr::filter(!primary_lineage %in% c("Failed", "Model Failed"))

  cluster_bundles <- valid_df |>
    dplyr::group_by(cluster_id) |>
    dplyr::summarise(
      input_data = list(data.frame(model, primary_lineage, detailed_subtype, confidence, reasoning)),
      .groups = "drop"
    )

  # 2. 内部仲裁函数
  arbitrate_worker <- function(cid, mdata) {
    opinions <- apply(mdata, 1, function(x) {
      glue::glue("Model: {x['model']} | Result: {x['primary_lineage']} - {x['detailed_subtype']} | Conf: {x['confidence']} | Logic: {x['reasoning']}")
    }) |> paste(collapse = "\n\n")

    sys_p <- "You are a Master Biologist. Arbitrate cell type conflicts.
    1. Align synonyms (e.g. T-cell = T lymphocyte). 2. Judge evidence. 3. Pick the most accurate labels.
    Return JSON: {cluster_id, consensus_lineage, consensus_subtype, agreement_score (0.0-1.0), status (Perfect/Majority/High Conflict), arbiter_comment}"

    api_res <- tryCatch({
      client$chat$completions$create(
        model = arbiter_model,
        messages = list(
          list(role="system", content=sys_p),
          list(role="user", content=glue::glue("Cluster {cid}:\n{opinions}"))
        ),
        temperature = 0.1, response_format = list(type="json_object")
      )
    }, error = function(e) NULL)

    if (is.null(api_res)) return(NULL)

    # 解析并强制转换类型 [CRITICAL FIX]
    res_raw <- jsonlite::fromJSON(api_res$choices[[1]]$message$content)
    res_df <- as.data.frame(res_raw)

    # 强制将所有列尤其是 cluster_id 转为字符，防止合并报错
    res_df <- res_df |> dplyr::mutate(dplyr::across(everything(), as.character))
    # 唯独分数转回数值
    res_df$agreement_score <- as.numeric(res_df$agreement_score)

    return(res_df)
  }

  # 3. 执行仲裁
  message(sprintf(">>> Arbitrating %d clusters using %s...", nrow(cluster_bundles), arbiter_model))

  res_list <- purrr::map(1:nrow(cluster_bundles), function(i) {
    arbitrate_worker(cluster_bundles$cluster_id[i], cluster_bundles$input_data[[i]])
  })

  # 过滤 NULL 结果并合并 [FIXED]
  final <- res_list |>
    purrr::compact() |>
    dplyr::bind_rows() |>
    dplyr::as_tibble()

  # 4. 统计与指标解读
  # Arbiter Intervened (仲裁介入): 只要分歧分数不是1，说明仲裁员处理了同义词或修正了冲突
  n_total <- nrow(final)
  n_perfect <- sum(final$agreement_score >= 0.95, na.rm = TRUE)
  n_fixed <- sum(final$agreement_score < 0.95, na.rm = TRUE)
  n_conflict <- sum(final$status == "High Conflict", na.rm = TRUE)

  message("\n========================================")
  message("  FINAL ARBITRATION REPORT (v8.2)")
  message("========================================")
  message(sprintf("Total Clusters      : %d", n_total))
  message(sprintf("  [✓] Perfect Consensus : %d", n_perfect))
  message(sprintf("  [!] Arbiter Adjusted  : %d (Fixed synonyms/minor gaps)", n_fixed))
  message(sprintf("  [X] High Conflict     : %d (Human review suggested)", n_conflict))
  message("========================================\n")

  return(final)
}
