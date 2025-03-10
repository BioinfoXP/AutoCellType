# AutoCellType - 单细胞转录组多模态智能注释工具包 🧬

![](https://img.shields.io/badge/R-4.2%2B-blue)
![](https://img.shields.io/badge/License-MIT-green)

AutoCellType是一个创新的单细胞转录组数据分析工具包，通过整合多个大语言模型(LLMs)的能力，为单细胞转录组数据提供智能化的细胞类型注释解决方案。该工具支持多种主流LLM模型的并行调用，可以根据不同注释场景灵活选择注释策略，显著提升注释的准确性和可靠性。

## ✨ 核心优势

- **多模型智能集成** 🤖: 支持同时调用多个LLM模型(如GPT-4、Claude、DeepSeek等)进行注释，充分利用不同模型的优势
- **灵活的注释粒度** 🎯: 支持major type到subtype的多层次注释，满足不同精细程度的分析需求
- **高度可配置** ⚙️: 可自定义API参数、重试策略、超时设置等，适应不同的使用场景
- **并行处理** ⚡: 采用并行计算架构，提高多模型场景下的注释效率

## 📦 安装指南

```r
remotes::install_github("irudnyts/openai", ref = "r6")
devtools::install_github("BioinfoXP/AutoCellType")
```

### 🔧 依赖安装

```r
# CRAN依赖
install.packages(c("dplyr", "purrr", "tibble", "parallel", "httr", "jsonlite",
                  "future", "future.apply", "lubridate", "ggplot2"))

# Bioconductor依赖
if (!require("BiocManager", quietly = TRUE))
    install.packages("BiocManager")
BiocManager::install("Seurat")
```

## 🚀 快速入门

### 1. 配置API密钥(兼容openai调用方式即可) 🔑

```r
Sys.setenv(OPENAI_API_KEY = "sk-your-key-here")       # API密钥
Sys.setenv(OPENAI_API_BASE_URL = "https://api.gpt.ge/v1")  # 服务端点
```

### 2. 基础注释（单模型调用） 📝

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

### 3. 多模型集成注释 🔄

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

### `AutoCellType` 函数 🛠️

| 参数             | 类型       | 默认值  | 说明                                              |
| ---------------- | ---------- | ------- | ------------------------------------------------- |
| input            | data.frame | 必选    | 输入marker矩阵，需包含cluster/gene/avg_log2FC三列 |
| annotation_level | character  | 'major' | 注释粒度: 'major'(大类)/'subtype'(亚型)           |
| model            | character  | 必选    | 语言模型选择: 'gpt-4o'/'deepseek-v3'等            |
| tissuename       | character  | 必选    | 组织类型描述，如"肺癌转移灶"                      |
| cellname         | character  | NULL    | 主细胞类型（亚型分析时必需），如"T细胞"           |
| topgenenumber    | integer    | 15      | 每个cluster使用的TOP基因数（推荐20-50）           |
| base_url         | character  | 必选    | API服务端地址                                     |
| api_key          | character  | 必选    | API认证密钥                                       |

### `RunMultipleAnnotations` 函数 🔄

| 新增参数         | 类型      | 默认值 | 说明                                      |
| ---------------- | --------- | ------ | ----------------------------------------- |
| models           | character | 必选   | 模型列表，如c('gpt-4o','claude-3-sonnet') |
| max_retries      | integer   | 3      | 单模型最大重试次数，建议3-5次             |
| timeout          | integer   | 300    | 单次API调用超时时间（秒）                 |
| parallel_workers | integer   | 4      | 并行工作线程数（建议≤CPU核心数）          |

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

<img src="https://wandering.oss-cn-hangzhou.aliyuncs.com/OB_Zotero/20250310115507.png" width="600" alt="结果展示">

## 💡 使用技巧

1. **基因数量选择** 📊
   - 大类注释：15-30基因
   - 精细亚型：30-50基因

2. **模型选择策略** 🤖

```r
# 推荐组合
optimal_models <- c(
    'claude-3-sonnet',  # 生物医学文献强项
    'gpt-4-turbo',      # 综合推理能力强
    'deepseek-v3'       # 中文支持优异
)
```

3. **异常处理** ⚠️

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

- 项目主页 🏠: https://github.com/BioinfoXP/AutoCellType
- 技术邮箱 📮: xp294053@163.com
- 微信公众号 💬: 桑树下的胖蚕宝

📱 扫码关注 📱

<img src="https://wandering.oss-cn-hangzhou.aliyuncs.com/OB_Zotero/20250310115328.png" width="200" height="200" alt="微信公众号二维码">

