#' Run Cell Type Annotation with Multiple Models
#'
#' @title RunMultipleAnnotations
#' @description Performs cell type annotation using multiple language models with retry mechanism
#' and parameter inheritance from AutoCellType.
#'
#' @inheritParams AutoCellType
#' @param models Character vector of model names to use
#' @param max_retries Integer. Maximum number of retry attempts (default: 3)
#'
#' @return A tibble containing combined annotation results with model agreement statistics
#'
#' @import dplyr
#' @import future
#' @import future.apply
#' @import tidyr
#' @import purrr
#' @import tibble
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
  # 验证输入
  validate_inputs <- function() {
    if (is.null(input)) {
      stop("Input data cannot be null")
    }
    if (!inherits(input, c("data.frame", "list"))) {
      stop("Input must be a data.frame or list of gene vectors")
    }
    if (length(models) == 0) {
      stop("No models specified")
    }
    if (is.null(api_key)) {
      stop("API key is required")
    }
    if (!annotation_level %in% c("major", "subtype")) {
      stop('annotation_level must be "major" or "subtype"')
    }
    if (annotation_level == "subtype" && is.null(cellname)) {
      warning("cellname is recommended for subtype annotation")
    }
  }

  # 检查依赖包
  check_dependencies <- function() {
    required_packages <- c("future", "future.apply", "dplyr", "tidyr", "purrr", "tibble")
    missing_packages <- required_packages[!sapply(required_packages, requireNamespace, quietly = TRUE)]
    if (length(missing_packages) > 0) {
      stop(sprintf("Missing required packages: %s", paste(missing_packages, collapse = ", ")))
    }
  }

  # 单个模型运行函数
  run_single_model <- function(model, retry_count = 0) {
    tryCatch({
      # 创建参数列表，仅包含AutoCellType接受的参数
      params <- list(
        input = input,
        tissuename = tissuename,
        cellname = cellname,
        annotation_level = annotation_level,
        custom_prompt = custom_prompt,
        model = model,
        topgenenumber = topgenenumber,
        base_url = base_url,
        api_key = api_key,
        timeout = timeout
      )

      # 移除NULL值的参数
      params <- params[!sapply(params, is.null)]

      # 使用do.call调用AutoCellType
      result <- do.call(AutoCellType, params)

      # 添加模型信息和时间戳
      result %>%
        dplyr::mutate(
          Model = model,
          Timestamp = Sys.time(),
          Attempt = retry_count + 1
        )
    }, error = function(e) {
      if (retry_count < max_retries) {
        warning(sprintf(
          "Attempt %d failed for model %s: %s. Retrying...",
          retry_count + 1, model, e$message
        ))
        Sys.sleep(2 ^ retry_count)  # 指数退避
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
    # 初始检查
    check_dependencies()
    validate_inputs()

    # 设置并行处理
    future::plan(future::multisession)

    # 并行运行多个模型
    results <- future.apply::future_lapply(
      models,
      function(model) run_single_model(model),
      future.seed = TRUE
    )

    # 合并结果
    combined_results <- results %>%
      purrr::compact() %>%
      dplyr::bind_rows() %>%
      dplyr::arrange(Cluster, Model) %>%
      dplyr::group_by(Cluster) %>%
      dplyr::mutate(
        Models_Used = paste(Model, collapse = ", ")
      ) %>%
      dplyr::ungroup()

    # 返回最终结果
    # dplyr::bind_rows(combined_results, summary_stats)

  }, error = function(e) {
    stop(sprintf("Error in RunMultipleAnnotations: %s", e$message))
  }, finally = {
    future::plan(future::sequential)
  })
}
