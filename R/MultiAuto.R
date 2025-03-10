#' Run Cell Type Annotation with Multiple Models
#'
#' @title RunMultipleAnnotations
#' @description Performs cell type annotation using multiple language models
#'
#' @inheritParams AutoCellType::AutoCellType
#' @param models Character vector of model names to use
#' @param max_retries Integer. Maximum number of retry attempts (default: 3)
#'
#' @return A data.frame containing combined annotation results
#'
#' @export
RunMultipleAnnotations <- function(
    input,
    tissuename = NULL,
    cellname = NULL,
    annotation_level = "major",
    custom_prompt = NULL,
    models = c("gpt-4o", "deepseek-v3"),
    topgenenumber = 10,
    base_url = "https://api.gpt.ge/v1",
    api_key = NULL,
    timeout = 30,
    max_retries = 3
) {
  # 单个模型运行函数
  run_single_model <- function(model, retry_count = 0) {
    tryCatch({
      result <- AutoCellType::AutoCellType(
        input = input,
        model = model,
        tissuename = tissuename,
        cellname = cellname,
        annotation_level = annotation_level,
        custom_prompt = custom_prompt,
        topgenenumber = topgenenumber,
        base_url = base_url,
        api_key = api_key,
        timeout = timeout
      )

      # 验证结果格式
      if (is.null(result) || nrow(result) == 0) {
        stop("Empty result returned from AutoCellType")
      }

      # 添加模型信息
      result$Model <- model
      result$Timestamp <- Sys.time()

      return(result)

    }, error = function(e) {
      if (retry_count < max_retries) {
        message(sprintf(
          "Attempt %d failed for model %s: %s. Retrying...",
          retry_count + 1, model, e$message
        ))
        Sys.sleep(2 ^ retry_count)
        return(run_single_model(model, retry_count + 1))
      } else {
        warning(sprintf(
          "All %d attempts failed for model %s: %s",
          max_retries, model, e$message
        ))
        return(NULL)
      }
    })
  }

  # 主执行流程
  tryCatch({
    # 顺序执行注释
    results <- list()
    for (model in models) {
      result <- run_single_model(model)
      if (!is.null(result)) {
        results[[length(results) + 1]] <- result
      }
    }

    if (length(results) == 0) {
      stop("No valid results obtained from any model")
    }

    # 简单合并结果
    combined_results <- do.call(rbind, results)

    # 如果存在Cluster列，则按其排序
    if ("Cluster" %in% colnames(combined_results)) {
      combined_results <- combined_results[order(combined_results$Cluster), ]
    }

    return(combined_results)

  }, error = function(e) {
    stop(sprintf("Error in RunMultipleAnnotations: %s", e$message))
  })
}
