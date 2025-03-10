# AutoCellType - 单细胞转录组自动注释工具

## 简介
AutoCellType是一个基于大语言模型的单细胞转录组自动注释工具包。它可以利用多个LLM模型对单细胞转录组数据进行细胞类型注释,支持不同粒度的注释级别。

## 安装
```r
# 从GitHub安装
devtools::install_github("username/AutoCellType")
```

## 主要功能
1. 单模型注释 (AutoCellType函数)
2. 多模型并行注释 (RunMultipleAnnotations函数)

## 使用示例

### 基本设置
```r
# 设置API参数
Sys.setenv(OPENAI_API_KEY = "your-api-key")
Sys.setenv(OPENAI_API_BASE_URL = "your-base-url") 
```

### 单模型注释
```r
result <- AutoCellType(
  input = markers,                # 输入marker基因表达矩阵
  annotation_level = 'subtype',   # 注释级别:major/subtype
  base_url = "https://api.gpt.ge/v1",
  api_key = "your-api-key",
  tissuename = "肝癌",           # 组织类型
  cellname = 't/nk',            # 大致细胞类型
  model = 'deepseek-v3',        # 使用的模型
  topgenenumber = 30            # 每个cluster使用的top基因数
)
```

### 多模型注释
```r
results <- RunMultipleAnnotations(
  input = markers,
  tissuename = '肝癌',
  cellname = 't/nk',
  annotation_level = 'subtype',
  models = c('deepseek-v3','gpt4o'),  # 可同时使用多个模型
  topgenenumber = 50,
  max_retries = 3,                     # 最大重试次数
  timeout = 300,                       # 超时时间(秒)
  base_url = "your-base-url",
  api_key = "your-api-key"
)

# 查看注释结果
results <- results %>% na.omit()
table(results$Cluster, results$Prediction)
```

## 参数说明

### AutoCellType函数
- input: marker基因表达矩阵
- annotation_level: 注释粒度('major'/'subtype') 
- base_url: API基础URL
- api_key: API密钥
- tissuename: 组织类型
- cellname: 大致细胞类型
- model: 使用的模型
- topgenenumber: 每个cluster使用的top基因数

### RunMultipleAnnotations函数
- 包含AutoCellType的所有参数
- models: 要使用的模型列表
- max_retries: API调用最大重试次数
- timeout: API调用超时时间(秒)

## 输出结果
- Cluster: 细胞群ID
- Prediction: 预测的细胞类型
- Status: 注释状态
- Model: 使用的模型
- Timestamp: 注释时间戳
- Models_Used: 使用的所有模型

## 注意事项
1. 使用前需要设置正确的API参数
2. 建议先用少量数据测试
3. 注意API调用限制和超时设置

## 依赖包
- dplyr
- purrr
- tibble
- parallel
- httr
- jsonlite

## 许可证
MIT
