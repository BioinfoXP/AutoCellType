# AutoCellType - 专家级单细胞多模态智能注释引擎 🧬

**AutoCellType** 是一个为解决单细胞注释“可解释性”与“鲁棒性”而生的生产级工具包。

传统的 LLM 注释工具往往采用“批处理”模式（将所有 Cluster 塞进一个 Prompt），这导致了严重的**注意力稀释（Attention Dilution）和位置偏见（Lost-in-the-Middle）**。AutoCellType 重构了底层交互逻辑，通过 **Single-Shot 并行架构** 与 **Chain-of-Thought（思维链）** 协议，将 AI 从“模式匹配机器”升级为具备溯源能力的“生物学推理引擎”。

---

## 🧠 深度架构解析

### 1. 注意力隔离架构 (Attention Isolation Architecture) 🎯

大模型在处理长文本时存在“注意力衰减”。当数十个细胞簇挤在一个请求中时，模型倾向于忽略中间的数据或产生幻觉。

* **解决方案**：AutoCellType 强制执行 **Single-Shot 策略**。每个细胞簇都在独立的线程中运行，拥有完整的 Context Window。
* **深度意义**：这不仅消除了“漏标”，更重要的是确保了模型对每个 Cluster 的 Marker 基因组进行**全权重（Full-Attention）**的扫描与分析，捕捉低表达但具有特异性的关键基因（如转录因子）。

### 2. 溯源式逻辑推演 (Abductive Reasoning Protocol) 🔍

我们拒绝“黑盒”式的标签输出。生物学结论必须建立在证据之上。

* **强制结构化推理**：通过严格的 JSON Schema，强制 LLM 在给出 `primary_lineage` 之前，必须先填写 `reasoning` 字段。
* **深度意义**：这迫使模型模拟生物学家的思维路径——先识别 Marker（如 *CD3D, CD8A*），再关联功能（*Cytotoxic*），最后推导结论（*CD8+ T cell*）。这种**“先思考，后回答”**的机制显著降低了幻觉率。

### 3. 语义熵减仲裁 (Semantic Entropy Reduction) ⚖️

多模型的一致性不仅仅是字符串匹配。`T-cell` 和 `T lymphocyte` 是字符串冲突，却是生物学共识。

* **LLM 仲裁器**：引入高阶模型作为 Arbiter，在语义空间而非字符空间评估一致性。
* **深度意义**：仲裁员不仅解决同义词问题，还能评估**证据信噪比**。当模型 A 基于高特异性 Marker 给出结论，而模型 B 基于泛 Marker 给出结论时，仲裁员会基于 `reasoning` 的质量进行加权裁决，而非简单的“少数服从多数”。

### 4. 自愈式工程底座 (Self-Healing Infrastructure) 🛡️

针对 LLM API 的不确定性，构建了容错层。

* **JSON 显微外科**：当 API 因 Token 限制截断输出时，内置解析器能识别破损的 JSON 结构（如未闭合的括号/引号）并自动进行语法修复，挽救宝贵的推理结果。
* **智能熔断**：自动区分“瞬时网络波动”（执行指数退避重试）与“致命请求错误”（如 400 Bad Request，立即熔断），大幅提升大规模任务的执行效率。

---

## 📦 安装

```r
# 1. 安装 OpenAI API 接口封装
remotes::install_github("irudnyts/openai", ref = "r6")

# 2. 安装 AutoCellType 核心包
devtools::install_github("BioinfoXP/AutoCellType")

```

---

## 🚀 深度应用工作流

### Phase 1: 注入先验知识的推理 (Informed Reasoning)

不同于盲注，AutoCellType 允许你将实验背景（Context）注入推理过程。

```r
library(AutoCellType)

# 配置环境
Sys.setenv(OPENAI_API_KEY = "sk-...", OPENAI_API_BASE_URL = "https://api.gpt.ge/v1")

# 运行推理引擎
# prior_info 是提升准确率的关键：它为模型划定了推理的边界条件
res <- AutoCellType(
    input = degs_df, 
    tissuename = "人肝癌微环境 (HCC)",
    
    # [深度技巧]：注入上游分析线索
    prior_info = "该数据来自 CD45+ 免疫细胞分选；SingleR 初步提示包含大量髓系细胞；请重点区分肿瘤相关巨噬细胞 (TAM) 的亚型。",
    
    n_cores = 8,          # 算力换时间：8线程并行
    model = "gpt-4o-mini" # 高效推理模型
)

```

### Phase 2: 多视角的对抗与共识 (Adversarial Consensus)

利用不同模型的训练偏差进行交叉验证，并通过仲裁器收敛结论。

```r
# 1. 引入"第二意见" (Second Opinion)
# 使用 deepseek-chat 作为对比模型，利用其不同的训练语料库
res_multi <- RunMultipleAnnotations(
    input = degs_df,
    models = c("gpt-4o-mini", "deepseek-chat"),
    tissuename = "人肝癌微环境",
    n_cores = 4
)

# 2. 启动仲裁庭 (The Tribunal)
# 使用推理能力最强的 gpt-4o 作为法官，审阅上述模型的证据链
final_consensus <- AssessModelConsensus(
    res_multi, 
    arbiter_model = "gpt-4o"
)

```

---

## 📊 结果解读：从数据到洞察

`AssessModelConsensus` 输出的不仅是结果，更是一份**质量诊断报告**。

| 状态 (Status) | 深度解读 | 建议操作 |
| --- | --- | --- |
| **Perfect Consensus** | **全息一致**。所有模型在语义和证据上均达成共识。 | ✅ 直接采信，无需复核。 |
| **Arbiter Adjusted** | **语义对齐**。模型间存在命名习惯差异（如 *NK cells* vs *Natural Killer cells*），仲裁员已将其统一。 | ✅ 采信仲裁结果。 |
| **Lineage Conflict** | **谱系冲突**。模型 A 认为是上皮，模型 B 认为是基质。通常暗示该簇包含双克隆（Doublets）或低质量细胞。 | ⚠️ 需回溯原始数据检查 QC 指标。 |
| **Subtype Ambiguity** | **亚型模糊**。大类一致，但对功能状态（如 *Exhausted* vs *Activated*）有分歧。这反映了生物学状态的连续性。 | 🔬 建议关注 `reasoning` 列中的通路证据。 |

---

## 📧 社区与支持

AutoCellType 致力于将**可解释 AI (XAI)** 引入单细胞分析领域。

* **GitHub**: [BioinfoXP/AutoCellType](https://github.com/BioinfoXP/AutoCellType)
* **Email**: xp294053@163.com
* **公众号**: 桑树下的胖蚕宝

*“In God we trust, all others must bring data (and reasoning).”*
