# 软件度量期末大作业实验报告

## libexpat Fuzzing by 唐子涵

### 1. 评测对象

| 字段 | 值 |
|---|---|
| 项目 | libexpat — C 语言实现的流式 XML 解析器 |
| 仓库 | https://github.com/libexpat/libexpat |
| 版本 | `R_2_8_1`（最新稳定版，commit `c7ffbf38`） |
| 代码规模 | `expat/lib/` 共 17,679 行 C 代码 |
| 选择理由 | 解析器类目标 attack surface 明确；历史 CVE 高发（CVE-2022-25235/25236 等）；被 Google OSS-Fuzz 长期覆盖，作为"难度对照"具有参考意义 |

### 2. 工具与环境

| 类别 | 工具 | 版本 / 备注 |
|---|---|---|
| 动态测试 | libFuzzer + AddressSanitizer | Homebrew LLVM 22.1.6 |
| 静态分析 | Clang Static Analyzer (`scan-build`) | 同上 |
| 构建 | CMake + clang | — |
| 平台 | macOS 14 / Apple Silicon | — |

**选 libFuzzer 而非 AFL++ 的理由**：macOS 原生支持更好，AFL++ 在 Apple Silicon 上 persistent mode / 共享内存有不稳定问题，多数情况下需要 Docker；libFuzzer 通过 `brew install llvm` 即装即用，作业文档示例也以 libFuzzer 风格组织。

### 3. 评测流程

```
源码 R_2_8_1
   │ CMake + -fsanitize=fuzzer-no-link,address
   ▼
libexpat.a (插桩静态库)
   │ link with LLVMFuzzerTestOneInput
   ▼
fuzz_xml 二进制 ──── 12h × 1 进程 + 字典 + 7 种子 ──── 245M execs / cov 4480
                                                            │
                                                            ▼
                                                    崩溃 0 / 慢输入 4（全部不可复现）

源码 R_2_8_1
   │ scan-build (Clang SA) + CMake
   ▼
3 个 core.NullPointerArithm 告警 ──── 逐个不变量分析 ──── 全部判定为误报
```

### 4. Driver 设计

`harness/libexpat/fuzz_xml.c`（核心节选）：

```c
#include <expat.h>

static void XMLCALL on_start(void *u, const XML_Char *n, const XML_Char **a) {(void)u;(void)n;(void)a;}
static void XMLCALL on_end  (void *u, const XML_Char *n)                     {(void)u;(void)n;}
static void XMLCALL on_chars(void *u, const XML_Char *s, int l)              {(void)u;(void)s;(void)l;}
static void XMLCALL on_comment(void *u, const XML_Char *d)                   {(void)u;(void)d;}
static void XMLCALL on_pi   (void *u, const XML_Char *t, const XML_Char *d)  {(void)u;(void)t;(void)d;}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    XML_Parser p = XML_ParserCreate(NULL);
    if (!p) return 0;
    XML_SetElementHandler(p, on_start, on_end);
    XML_SetCharacterDataHandler(p, on_chars);
    XML_SetCommentHandler(p, on_comment);
    XML_SetProcessingInstructionHandler(p, on_pi);
    XML_Parse(p, (const char *)data, (int)size, /*isFinal=*/1);
    XML_ParserFree(p);
    return 0;
}
```

设计要点：

- **显式注册 5 类 handler**：不注册会让 expat 走 fast-path，损失约 30% 覆盖
- **单 buffer 一次性 parse**：简化驱动，省略 `XML_GetBuffer` / `XML_ParseBuffer` 流式路径
- **handler 不做实际工作**：仅触发回调路径，避免引入驱动自身 bug 干扰 sanitizer 信号

![driver 源码](assets/driver-code.png)

### 5. 种子语料与字典

| 资源 | 数量 / 大小 | 覆盖特性 |
|---|---|---|
| 手工种子 | 7 个，共 28 KB | basic / attrs / namespaces / cdata / DOCTYPE+entities / comments+PI / UTF-8 |
| XML 字典 | 63 条 token | XML 声明、CDATA、DOCTYPE、ENTITY、实体引用、BOM、属性语法等 |

字典经验证有效——运行时输出中可观察到 `DE: "&lt;"` 之类的"Manual Dictionary"变异标记，说明字典 token 实际参与了变异。

### 6. 动态测试结果

#### 6.1 12 小时运行统计

| 指标 | 数值 |
|---|---|
| 总执行次数 | 245,076,849 |
| 平均 exec/s | 5,608 |
| 最终 cov（PC 计数器命中） | **4,480** / 模块总量 8,076 (**55.5%**) |
| 最终 ft（features） | 16,997 |
| 工作语料 | 25,458 文件（精华去重 8,222 条 / 1.52 MB） |
| 新增有效用例 | 99,225 |
| 内存峰值 | 698 MB |
| **崩溃 / Sanitizer 报错** | **0** |
| 超时输入（slow-unit） | 4 个（全部不可复现，详见 §6.3） |

![libFuzzer 12 小时运行收尾终端](assets/fuzzing-completion.png)

#### 6.2 覆盖率趋势

![libexpat libFuzzer 12h coverage trend](assets/coverage.png)

X 轴时间通过 `t = execs × T_total / execs_total` 由日志重建（libFuzzer 不打时间戳），总时长锚定到 `Done 245076849 runs in 43697 second(s)`。

关键观察：

- **0 → 2.1 h**：cov 从 2915 急升到 ~4250（增量 1335 PCs）
- **t ≈ 2.1 h**：判定饱和（次小时 cov 增长 < 1% × final）
- **2.1 → 12 h**：缓增至 4480，边际收益接近 0
- **ft 走势与 cov 同步**：每条新边带来多个 features，曲线更平滑

注：12h 起点 cov 已是 2915 而非冷启动值，因前序烟雾测试遗留 3205 个语料文件被本次运行作为初始 corpus 复用。

#### 6.3 slow-unit triage

| 文件 | 大小 | 重测耗时 | 判定 |
|---|---|---|---|
| `slow-unit-0e9c…` | 25 B | 0.07 s | 系统抖动假阳性 |
| `slow-unit-6599…` | 30 B | 0.03 s | 同上 |
| `slow-unit-6691…` | 3208 B | 0.03 s | 同上 |
| `slow-unit-e9a2…` | 874 B | 0.03 s | 同上 |

12 小时跑出的"最慢单次"`stat::slowest_unit_time_sec = 1044`（17 分钟），单独重跑全部 < 100 ms，推断是 macOS 后台任务（Spotlight 索引 / Time Machine）占用导致的瞬时调度延迟，**非算法复杂度 bug**。

### 7. 静态分析结果

`scan-build` 报告 3 个 `core.NullPointerArithm` 警告，全部位于 `xmlparse.c` 的 `poolGrow()` 字符串池扩容路径。**经完整不变量分析，确认全部为误报**。

![scan-build HTML 报告](assets/scan-build-report.png)

#### 7.1 STRING_POOL 对象不变量

```
INV: pool->ptr == NULL  ⇔  pool->start == NULL    (两指针同生同灭)
```

全文件中 `pool->ptr` 的 6 处赋值均维护此不变量：

| 行号 | 函数 | `ptr` 赋值 | 同时 `start` 状态 |
|---|---|---|---|
| 7937 | `poolInit`   | `NULL`                  | 同行 `start = NULL` |
| 7957 | `poolClear`  | `NULL`                  | 同行 `start = NULL` |
| 8105 | `poolGrow` 路径 1a | `pool->start`     | 紧前置 `start = blocks->s`（非 NULL） |
| 8115 | `poolGrow` 路径 1b | `blocks->s + offset` | 紧后置 `start = blocks->s`           |
| 8149 | `poolGrow` 路径 2  | `blocks->s + offset` | 紧后置 `start = blocks->s`           |
| 8192 | `poolGrow` 路径 3  | `tem->s + offset`    | 紧后置 `start = tem->s`              |

#### 7.2 三个告警逐个判定

| 行 | 告警表达式 | 反驳依据 |
|---|---|---|
| 8115 | `pool->ptr - pool->start` | 进入分支前第 8099 行已检查 `start != NULL` ⇒ 由不变量 `ptr != NULL` |
| 8128 | `pool->ptr - pool->start` | 第 8121 行检查 `pool->blocks && start == blocks->s`；`blocks->s` 是 flex array，永远非 NULL ⇒ `start` 非 NULL ⇒ `ptr` 非 NULL |
| 8191 | `pool->ptr - pool->start` (memcpy 内) | 紧邻的 `pool->ptr != pool->start` 已隐含至少一边非 NULL ⇒ 由不变量两者均非 NULL |

#### 7.3 误报根因与改进

Clang SA 是**单函数路径敏感**分析器，不能跨函数证明 `STRING_POOL` 这种**对象级状态不变量**。可缓解的做法：

- 在敏感点添加 `assert(pool->ptr != NULL);` 给分析器路径约束提示
- 用 SMT-based 工具（如 CBMC）做可证明的全程序推理
- 或重构 `STRING_POOL` 让 `ptr` / `start` 通过单一构造点初始化、消除"可能 NULL"的状态空间

### 8. 结论

| 维度 | 结论 |
|---|---|
| 动态测试 | 12 小时未发现真实崩溃；覆盖在 t ≈ 2 h 后饱和 |
| 静态分析 | 3 个告警均为误报，揭示 SA 工具对状态不变量的固有局限 |
| 上游 bug | 无可提交 |

**未发现真实问题的合理解释**：

1. **OSS-Fuzz 长期覆盖**：libexpat 是 Google OSS-Fuzz 的常驻目标，已累计被等价或更强的 fuzzer 跑过数万 CPU-hour，浅层 bug 早被修复。
2. **R_2_8_1 是 2024 年稳定版**：近期所有公开 CVE 修复都已包含。
3. **本 driver 表面有限**：只接 `XML_ParserCreate + XML_Parse` 一条路径，未覆盖 `XML_ExternalEntityParserCreate`（外部实体——历史 CVE 高发）、`XML_GetBuffer + XML_ParseBuffer`（流式分块）、不同 `XML_Char` 宽度等接口。

**可改进方向**：

- **扩展 driver 多入口**：补外部实体、流式分块、多次 reset 等路径，预期 cov 上限可从 4480 升至 5500+
- **结构化 fuzz**：libexpat 自带 `fuzz/xml_lpm_fuzzer.cpp` 使用 protobuf 描述合法 XML 结构，比无脑字节变异更高效
- **差分 fuzz**：将 libexpat 与 libxml2 对同一输入的解析结果交叉比对，发现"非崩溃但行为不一致"的 bug

### 9. Agent 工具流设计（开放题）

本次实验全程由 Claude Code 作为 AI 编程助手参与（环境搭建、driver 撰写、日志分析、误报判定），可视为初步的 Agent 应用。设想一个更完整的"漏洞挖掘 Agent" 工作流：

```
┌────────────┐   ┌──────────────┐   ┌──────────────┐
│ 项目源码    │──>│ 入口推荐 + 阅读│──>│ Driver 自动生成 │
└────────────┘   └──────────────┘   └──────────────┘
                                              │
                                              ▼
                  ┌──────────────────┐  ┌──────────────┐
                  │ 覆盖率反馈循环    │<─│ 编译并运行 fuzz│
                  │ (调参 / 字典扩展)  │  └──────────────┘
                  └──────────────────┘
                            │
                ┌───────────┴────────────┐
                ▼                        ▼
        ┌─────────────┐         ┌────────────────┐
        │ 崩溃 triage  │         │ 静态分析告警    │
        │ 聚类 + 根因   │         │ 真伪 (TP/FP) 判定│
        └─────────────┘         └────────────────┘
                │                        │
                └────────────┬───────────┘
                             ▼
                  ┌──────────────────┐
                  │ Issue / PoC 草稿  │
                  └──────────────────┘
```

各环节具体设计：

| 环节 | Agent 行为 | 工具 / 模型 |
|---|---|---|
| 入口推荐 | 读 README / 头文件 / 测试代码，识别 public API 中"接收外部数据"的函数 | LLM + grep / ast-grep |
| Driver 生成 | 模仿现有测试代码风格，自动写 `LLVMFuzzerTestOneInput` | LLM + 项目示例 few-shot |
| Fuzz 调度 | 监控 cov 增长率，自动调 `-max_len` / 重启 worker / 触发种子精简 | shell + libFuzzer + 监控脚本 |
| 崩溃 triage | 对崩溃做 stack 聚类，调 lldb/gdb 给出根因假设 | LLM + lldb |
| **SA 告警判定** | 按 §7 的不变量分析模式，定位赋值点、推断对象不变量、判 TP/FP | LLM + tree-sitter / clangd |
| Issue 生成 | 根因 + 最小 PoC + 影响版本范围整理成上游可接受的 issue 文本 | LLM + 项目历史 issue few-shot |

**最具落地价值的两个环节**：

1. **SA 告警真伪判定**：本报告 §7 的工作模板化后，可以让"几十甚至几百条告警"变成有限的人力检查量。这对企业代码大批量接入静态分析的场景价值很高。
2. **Crash triage**：fuzz 跑出几千个崩溃时去重并选出"值得花人力看的那个"。

**与本次实验的结合**：本项目中"分析 3 个 NullPointerArithm 告警 → 推导不变量 → 判定为误报"这条链路，正是 Agent 流程中"SA 告警判定"节点的人工版执行。整套分析可以模板化，未来通过 Agent 自动化。

### 附录：项目结构

```
fuzzing/
├── targets/libexpat/                # libexpat R_2_8_1 (git submodule, c7ffbf38)
├── harness/libexpat/
│   ├── fuzz_xml.c                   # 手写 driver
│   ├── build.sh                     # 编译 fuzzer
│   ├── run.sh                       # 12h fuzz 入口
│   ├── scan.sh                      # 静态分析
│   ├── xml.dict                     # 63 条 XML 字典
│   └── plot_coverage.py             # 覆盖趋势画图
├── corpus/libexpat/seeds/           # 7 个手工种子
└── build/                           # 运行时产物（gitignored）
    ├── fuzz_xml                     # fuzzer 二进制
    ├── corpus/libexpat/             # 工作语料
    ├── findings/libexpat/           # 崩溃 / slow-unit
    ├── logs/libexpat/               # 完整运行日志
    ├── plots/libexpat/coverage.png  # §6.2 图源
    └── scan-report/libexpat/…       # scan-build HTML 报告
```
