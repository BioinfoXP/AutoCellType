

# AutoCellType - 单细胞转录组多模态智能注释工具包

![](https://img.shields.io/badge/R-3.6%2B-blue)
![](https://img.shields.io/badge/License-MIT-green)

基于大语言模型的单细胞转录组细胞类型注释工具，支持多模型智能标注与结果整合。

## 📦 安装指南

```r
remotes::install_github("irudnyts/openai", ref = "r6")
devtools::install_github("username/AutoCellType")
```

### 依赖安装

```r
# CRAN依赖
install.packages(c("dplyr", "purrr", "tibble", "parallel", "httr", "jsonlite",
                   "future", "future.apply", "lubridate", "ggplot2"))

# Bioconductor依赖
if (!require("BiocManager", quietly = TRUE))
  install.packages("BiocManager")
BiocManager::install("Seurat")

# 可选可视化包
install.packages(c("patchwork", "scRNAtoolVis", "TheBestColors"))
```


## 🚀 快速入门

### 1. 配置API密钥(兼容openai调用方式即可)

```r
Sys.setenv(OPENAI_API_KEY = "sk-your-key-here")       # API密钥
Sys.setenv(OPENAI_API_BASE_URL = "https://api.gpt.ge/v1")  # 服务端点
```

### 2. 基础注释（单模型调用）

```r
library(AutoCellType)

# 载入示例数据集
data(sample_markers)

# 单模型注释
basic_result <- AutoCellType(
  input = sample_markers,
  annotation_level = 'subtype',
  tissuename = "肝癌微环境",
  cellname = 'T细胞',
  model = 'deepseek-v3'
)
```

### 3. 多模型集成（单模型调用）

```r
# 并行多模型注释
multi_result <- RunMultipleAnnotations(
  input = sample_markers,
  models = c('gpt-4o', 'deepseek-v3'),
  tissuename = "肝细胞癌组织",
  cellname = '内皮细胞',
  topgenenumber = 40,
  max_retries = 5,
  timeout = 600
)
```


## 📚 核心函数详解

### `AutoCellType` 函数


| 参数             | 类型       | 默认值  | 说明                                                  |
| ---------------- | ---------- | ------- | ----------------------------------------------------- |
| input            | data.frame | 必选    | 输入marker矩阵，需包含cluster/gene/avg_log2FC三列     |
| annotation_level | character  | 'major' | 注释粒度: 'major'(大类)/'subtype'(亚型)               |
| model            | character  | 必选    | 语言模型选择: 'gpt-4o'/'deepseek-v3'等                |
| tissuename       | character  | 必选    | 组织类型描述，如"肺癌转移灶"                          |
| cellname         | character  | NULL    | 主细胞类型（亚型分析时必需），如"T细胞"、"成纤维细胞" |
| topgenenumber    | integer    | 15      | 每个cluster使用的TOP基因数（推荐范围：20-50）         |
| base_url         | character  | 必选    | API服务端地址                                         |
| api_key          | character  | 必选    | API认证密钥                                           |


  ### `RunMultipleAnnotations` 函数


| 新增参数         | 类型      | 默认值 | 说明                                        |
| ---------------- | --------- | ------ | ------------------------------------------- |
| models           | character | 必选   | 模型列表，例如c('gpt-4o','claude-3-sonnet') |
| max_retries      | integer   | 3      | 单模型最大重试次数，建议3-5次               |
| timeout          | integer   | 300    | 单次API调用超时时间（秒）                   |
| parallel_workers | integer   | 4      | 并行工作线程数（建议不超过CPU核心数）       |

  ## 🔍 结果解析


  ```r
# 查看简洁结果
head(results[, c("Cluster", "Prediction", "Model")])

# 结果统计
library(dplyr)
results %>%
  group_by(Cluster, Model) %>%
  summarise(Dominant_Type = names(which.max(table(Prediction))),
            Confidence = max(table(Prediction))/n())
  ```


## 💡 使用技巧

1. **基因数量选择**

  - 大类注释：15-30基因
- 精细亚型：30-50基因

2. **模型选择策略**

  ```r
# 推荐组合
optimal_models <- c(
  'claude-3-sonnet',  # 生物医学文献强项
  'gpt-4-turbo',      # 综合推理能力强
  'deepseek-v3'       # 中文支持优异
)
  ```

3. **异常处理**

  ```r
tryCatch({
  result <- AutoCellType(...)
}, error = function(e) {
  message("遇到API错误: ", e$message)
  saveRDS(markers, "backup_markers.rds")  # 自动保存当前进度
})
  ```


## ❓ 常见问题

  - 降低并行数 `parallel_workers=2`
- 启用指数退避重试 `backoff=TRUE`
- 联系服务商提升配额


## 📧 支持与联系

遇到问题请提交issue或联系:

  - 项目主页: https://github.com/BioinfoXP/AutoCellType
- 技术邮箱: xp294053@163.com
- 微信公众号: 桑树下的胖蚕宝📧扫码关注📧

![image-20250310114525554](C:\Users\Wandering\AppData\Roaming\Typora\typora-user-images\image-20250310114525554.png)

