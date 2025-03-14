#' Automated Cell Type Annotation with GPT Models
#'
#' @title AutoCellType
#' @description Leverages GPT models to annotate cell clusters based on marker genes.
#'
#' @param input A differential expression matrix (data.frame) with columns 'cluster', 'gene' and 'avg_log2FC',
#' or a predefined list of gene vectors.
#' @param tissuename Character string specifying tissue type.
#' @param cellname Optional character string specifying cell type for subtype annotation.
#' @param annotation_level Level of annotation: "major" or "subtype" (default: "major").
#' @param custom_prompt Optional custom prompt for GPT model.
#' @param model Model name (default: "gpt-4o").
#' @param topgenenumber Number of top marker genes per cluster (default: 10).
#' @param base_url API endpoint URL.
#' @param api_key API key.
#' @param timeout Network timeout in seconds (default: 30).
#' @param retries Maximum retry attempts (default: 3).
#'
#' @return A tibble with columns: Cluster, Prediction, Annotation_Level, Status
#' @export
#'
#' @importFrom httr POST timeout
#' @importFrom dplyr filter group_by slice_max summarise
#' @importFrom tibble deframe tibble
#' @importFrom purrr map safely
#' @importFrom glue glue
#' @importFrom stringr str_split str_extract
#' @importFrom openai OpenAI
#'
AutoCellType <- function(
    input,
    tissuename = NULL,
    cellname = NULL,
    annotation_level = "major",
    custom_prompt = NULL,
    model = "gpt-4o",
    topgenenumber = 15,
    base_url = "https://api.gpt.ge/v1",
    api_key = NULL,
    timeout = 30,
    retries = 3
) {
  # 检查依赖包
  check_dependencies <- function() {
    required_packages <- c("openai", "dplyr", "httr", "purrr", "glue", "stringr", "tibble")
    missing_packages <- required_packages[!sapply(required_packages, requireNamespace, quietly = TRUE)]
    if (length(missing_packages) > 0) {
      stop(sprintf("Missing required packages: %s", paste(missing_packages, collapse = ", ")))
    }
  }

  # 输入验证
  validate_inputs <- function(input, topgenenumber, annotation_level, cellname) {
    if (is.null(input)) {
      stop("Input data is required.")
    }

    if (!inherits(input, c("data.frame", "list"))) {
      stop("Input must be a data.frame or list of gene vectors.")
    }

    if (length(input) == 0) {
      stop("Input data is empty.")
    }

    if (!is.numeric(topgenenumber) || topgenenumber <= 0) {
      stop("topgenenumber must be a positive integer.")
    }

    if (!annotation_level %in% c("major", "subtype")) {
      stop('annotation_level must be "major" or "subtype".')
    }

    if (annotation_level == "subtype" && is.null(cellname)) {
      warning("cellname is recommended for subtype annotation.")
    }

    if (inherits(input, "data.frame")) {
      required_cols <- c("cluster", "gene", "avg_log2FC")
      missing_cols <- setdiff(required_cols, colnames(input))
      if (length(missing_cols) > 0) {
        stop(sprintf("Missing required columns: %s", paste(missing_cols, collapse = ", ")))
      }
    }
  }

  # 初始化API客户端
  initialize_client <- function(api_key, base_url) {
    if (is.null(api_key)) {
      api_key <- Sys.getenv("OPENAI_API_KEY")
      if (api_key == "") {
        stop("API key not found. Please provide api_key or set OPENAI_API_KEY environment variable.")
      }
    }
    tryCatch(
      openai::OpenAI(api_key = api_key, base_url = base_url),
      error = function(e) stop(sprintf("Failed to initialize API client: %s", e$message))
    )
  }

  # 处理输入数据
  process_input_data <- function(input, topgenenumber) {
    tryCatch({
      if (inherits(input, "data.frame")) {
        input %>%
          dplyr::filter(avg_log2FC > 0) %>%
          dplyr::group_by(cluster) %>%
          dplyr::slice_max(order_by = avg_log2FC, n = topgenenumber) %>%
          dplyr::summarise(genes = paste0(gene, collapse = ",")) %>%
          tibble::deframe()
      } else {
        sapply(input, paste0, collapse = ",")
      }
    }, error = function(e) {
      stop(sprintf("Error processing input data: %s", e$message))
    })
  }

  # 生成系统提示
  generate_prompt <- function(custom_prompt, annotation_level, tissuename, cellname) {
    if (!is.null(custom_prompt)) return(custom_prompt)

    base_prompt <- "你是一位单细胞注释专家，你对肿瘤微环境内细胞具有深入的理解，"
    if (annotation_level == "major") {
      glue::glue(
        "{base_prompt}
        你会对{tissuename}样本的主要细胞类型进行分析，并结合专业知识及分子标记，
        给我你判断的细胞类型，你可首先判断基质/免疫细胞，
        随后进一步依据Marker分子确定最终的细胞类型，注释结果务必符合学术规范和文献报道。"
      )
    } else {
      glue::glue(
        "{base_prompt}
        你会对{tissuename}样本的{cellname}细胞类型进行亚群分析，并结合专业知识及分子标记，
        你会依据细胞大群类型，对细胞大群依据Marker分子确定细胞类型，
        如果marker不显著，考虑功能注释，
        注释结果务必符合学术规范和文献报道。"
      )
    }
  }

  # 处理批次
  process_batch <- function(cluster_ids, markers, client, model, system_prompt, retries) {
    user_prompt <- glue::glue(
      "Annotate the following cell clusters:\n{glue::glue_collapse(cluster_ids, sep = '\n')}\n\nStrictly follow the response format: 'Cluster_name: Cell_type'."
    )

    safe_request <- purrr::safely(function() {
      response <- client$chat$completions$create(
        model = model,
        messages = list(
          list(role = "system", content = system_prompt),
          list(role = "user", content = user_prompt)
        ),
        temperature = 0.1,
        max_tokens = 200
      )

      if (!is.null(response)) {
        parsed <- stringr::str_split(response$choices[[1]]$message$content, "\n")[[1]]
        valid_lines <- stringr::str_extract(parsed, "^\\s*Cluster\\w+:\\s+.+")
        valid_lines <- valid_lines[!is.na(valid_lines)]
        if (length(valid_lines) == length(cluster_ids)) {
          return(setNames(stringr::str_extract(valid_lines, "(?<=:)\\s*[^\\s]+"), cluster_ids))
        }
      }
      NULL
    })

    result <- NULL
    attempt <- 0
    while (is.null(result) && attempt < retries) {
      result <- safe_request()$result
      attempt <- attempt + 1
      if (is.null(result) && attempt < retries) Sys.sleep(1)
    }

    result %||% setNames(rep(NA_character_, length(cluster_ids)), cluster_ids)
  }

  # 主执行流程
  tryCatch({
    # 初始检查
    check_dependencies()
    validate_inputs(input, topgenenumber, annotation_level, cellname)

    # 初始化客户端和处理数据
    client <- initialize_client(api_key, base_url)
    markers <- process_input_data(input, topgenenumber)
    system_prompt <- generate_prompt(custom_prompt, annotation_level, tissuename, cellname)

    # 批处理
    cluster_list <- names(markers)
    batch_size <- 5
    batch_indices <- split(seq_along(cluster_list), ceiling(seq_along(cluster_list) / batch_size))

    results <- purrr::map(batch_indices, function(indices) {
      current_batch <- markers[indices]
      process_batch(names(current_batch), current_batch, client, model, system_prompt, retries)
    })

    # 返回结果
    tibble::tibble(
      Cluster = unlist(lapply(results, names)),
      Prediction = unlist(results),
      Annotation_Level = annotation_level,
      Status = ifelse(is.na(unlist(results)), "Failed", "Success")
    )
  }, error = function(e) {
    stop(sprintf("Error in AutoCellType: %s", e$message))
  })
}
