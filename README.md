# AutoCellType: 基于逻辑推理与多模态共识的单细胞智能注释框架

**AutoCellType** 是一个专为单细胞转录组数据设计的自动化注释工具包。针对当前大语言模型（LLM）在生物信息学应用中存在的**幻觉（Hallucination）**、**上下文注意力稀释（Context Dilution）**以及**语义异质性（Semantic Heterogeneity）**问题，AutoCellType 提出了一套工程化解决方案。

本工具摒弃了传统的“批处理”模式，通过 **Single-Shot 并行架构**、**思维链（Chain-of-Thought, CoT）约束**以及**多模型仲裁机制**，实现了从 Marker 基因列表到细胞身份的高精度、可解释性推断。

---

## 📐 核心架构与方法论

### 1. 独立上下文并行处理 (Isolated Context Parallelism)

传统方法常将多个细胞簇拼接在单一 Prompt 中，导致模型受限于上下文窗口（Context Window）的注意力衰减，易产生漏标或错误关联。

* **机制**：AutoCellType 采用 **Single-Shot Strategy**，为每一个 Cluster 分配独立的线程与推理上下文。
* **优势**：确保模型对每个亚群的 Marker 特征（尤其是低表达的高特异性基因）具有完全的注意力权重，消除“位置偏见（Lost-in-the-middle）”。

### 2. 结构化思维链约束 (Structured Chain-of-Thought)

仅依赖 Marker 匹配名称容易导致缺乏生物学依据的推断。

* **机制**：引入强制性的 JSON Schema 约束，要求模型在输出 `primary_lineage` 前，必须先生成 `reasoning` 字段。模型需显式构建从基因表达（如 *CD3D+, CD8A+*）到功能状态（*Cytotoxic*）再到细胞身份的逻辑链路。
* **优势**：将“黑盒”预测转化为可验证的生物学推理过程，显著降低幻觉率。

### 3. 先验知识注入 (Context-Aware Inference)

细胞类型的定义高度依赖于组织微环境与实验背景。

* **机制**：通过 `prior_info` 参数支持多模态证据注入。用户可传入组织来源、流式分选背景、通路富集评分（GSEA/GO）或参考数据集（Reference-based）的初步预测结果。
* **优势**：模型能够结合先验分布与观测数据（Marker）进行贝叶斯式的综合推断，解决同名异质（Heterogeneity）问题。

### 4. 语义对齐与仲裁 (Semantic Alignment & Arbitration)

不同模型（如 GPT-4o, DeepSeek）对同一细胞类型的命名习惯可能不同（如 *T lymphocyte* vs *T cell*），这并非生物学分歧。

* **机制**：内置 **LLM Arbiter** 模块。仲裁器在语义空间而非字符空间评估一致性，能够合并同义词，并根据各模型的证据质量（Reasoning Quality）进行加权裁决。
* **优势**：有效区分“命名差异”与“生物学冲突”，提供清洗后的高置信度共识结果。

---

## 📦 安装

```r
# 1. 安装 OpenAI API 接口封装 (R6 类支持)
remotes::install_github("irudnyts/openai", ref = "r6")

# 2. 安装 AutoCellType 核心包
devtools::install_github("BioinfoXP/AutoCellType")

```

---

## 💻 标准工作流

### 环境配置

```r
Sys.setenv(OPENAI_API_KEY = "sk-xxxxxxxx") 
Sys.setenv(OPENAI_API_BASE_URL = "https://api.gpt.ge/v1")

```

### 场景一：高精度单模型注释

适用于对注释深度和可解释性有较高要求的常规分析。

```r
library(AutoCellType)

# 启动推理引擎
# n_cores: 控制并发度，实现高吞吐量处理
res <- AutoCellType(
    input = degs_df,                # Seurat FindAllMarkers 输出
    tissuename = "人肝癌微环境 (HCC)", 
    prior_info = "样本来源于 CD45+ 免疫细胞分选；需重点区分 TAM 亚型", 
    n_cores = 8,                    
    model = "gpt-4o-mini"           
)

```

### 场景二：多模型集成与共识仲裁

适用于复杂组织或存在争议的亚群定义，利用模型间的异质性进行交叉验证。

```r
# 1. 多模型并行推理 (Ensemble Inference)
# 获取不同训练背景下的模型观点
res_multi <- RunMultipleAnnotations(
    input = degs_df,
    models = c("gpt-4o-mini", "deepseek-chat"),
    tissuename = "人肝癌微环境",
    n_cores = 4
)

# 2. 语义仲裁与冲突消解 (Arbitration)
# 评估一致性，生成最终共识报告
final_report <- AssessModelConsensus(
    res_multi, 
    arbiter_model = "gpt-4o"
)

```

---

## 📊 结果指标解读

`AssessModelConsensus` 提供定量化的置信度评估指标：

| 状态 (Status) | 技术解读 | 处理建议 |
| --- | --- | --- |
| **Perfect Consensus** | **语义一致**。所有模型在 Lineage 和 Subtype 层面均达成共识，且证据链完整。 | ✅ 采信 |
| **Arbiter Adjusted** | **语义归一化**。仲裁器识别并统一了不同模型的同义词命名（Synonym Resolution），或基于更强证据修正了次优结论。 | ✅ 采信仲裁结果 |
| **High Conflict** | **生物学冲突**。模型间存在谱系级（Lineage-level）分歧，通常提示该簇可能为 Doublets、低质量细胞或过渡态细胞。 | ⚠️ 需人工核查原始表达谱 |

---

## 🛡️ 工程鲁棒性设计

AutoCellType 在设计时充分考虑了 API 的不稳定性与数据格式的复杂性：

1. **致命错误熔断**：自动识别 HTTP 400 等不可恢复错误，立即终止并报告，避免无效的指数退避重试。
2. **结构化数据修复**：内置 JSON 语法修复器，自动处理因 Token 上限导致的截断（Premature EOF），保障数据完整性。
3. **类型安全保障**：严格处理 R 语言中 Cluster ID 的数值/字符类型转换，确保输入输出的一一对应。

---

## 📧 社区与反馈

如果您在单细胞研究中遇到特殊的注释难题，或有关于算法改进的建议，欢迎通过以下渠道联系：

* **GitHub Issues**: [BioinfoXP/AutoCellType](https://github.com/BioinfoXP/AutoCellType)
* **Email**: xp294053@163.com
* **WeChat Official**: 桑树下的胖蚕宝

*AutoCellType 致力于通过计算工程学方法，提升 LLM 在生物医学领域的推理可靠性。*
