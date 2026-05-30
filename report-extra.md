# cJSON / zlib / libmicrodns 10 分钟烟雾测试报告

## 1. 实验设置

本次在原有 libFuzzer + AddressSanitizer 工具链上新增三个评测对象：cJSON、zlib、libmicrodns。源码当前位于 `targets/targets/<proj>`，harness 位于 `harness/<proj>`。

三个项目均使用 Homebrew LLVM clang 19.1.5 构建，显式指定 macOS SDK：`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`。每个项目运行 10 分钟，`-max_len=4096`，并使用项目对应字典和种子语料。

| 项目 | Driver | 运行日志 |
|---|---|---|
| cJSON | `harness/cjson/fuzz_cjson.c` | `build/logs/cjson/fuzz-20260529-193957.log` |
| zlib | `harness/zlib/fuzz_zlib.c` | `build/logs/zlib/fuzz-20260529-193957.log` |
| libmicrodns | `harness/libmicrodns/fuzz_mdns.c` | `build/logs/libmicrodns/fuzz-20260529-193957.log` |

## 2. Driver 设计

### cJSON

Driver 使用 `cJSON_ParseWithLengthOpts` 解析输入，解析成功后递归遍历 JSON tree，触发类型判断 API，再调用 `cJSON_PrintUnformatted` 触发序列化路径，最后 `cJSON_Delete` 释放对象。

### zlib

Driver 将输入同时喂给两种 inflate 模式：

- `inflateInit2(..., 15 + 32)`：自动识别 zlib / gzip wrapper
- `inflateInit2(..., -15)`：raw deflate

每轮最多执行 256 次 `inflate`，避免恶意输入导致过长循环。

### libmicrodns

Driver 复用项目自带 fuzz 思路：调用内部 `mdns_parse` 解析 DNS/mDNS packet，成功后调用 `mdns_write` 写回，再用 `mdns_free` 释放解析出的 RR 链表。种子包含 PTR query 和带压缩 name pointer 的 PTR response。

## 3. 10 分钟动态测试结果

| 项目 | 总执行 | 最终 cov | 最终 ft | corpus | 平均/末尾 exec/s | crash/OOM/timeout |
|---|---:|---:|---:|---:|---:|---|
| cJSON | 45,264,138 | 302 | 1,849 | 550 | 70,777 | 0 / 0 / 0 |
| zlib | 2,755,849 | 417 | 1,492 | 482 | 4,585 | 0 / 0 / 0 |
| libmicrodns | 28,670,519 | 147 | 678 | 250 | 35,826 | 0 / 0 / 0 |

三者在 10 分钟内均未产生 `crash-*`、`oom-*` 或 `timeout-*` artifact。

初步观察：

- cJSON 执行速度最高，约 45M 次输入；前 10 秒覆盖率快速到达 302 PCs，之后主要增长 features 和 corpus，PC 覆盖进入平台期。
- zlib 执行速度最低，主要因为 driver 同时尝试 gzip/zlib wrapper 和 raw deflate 两条路径，且解压循环成本高；但覆盖率在 10 分钟内仍从 190 PCs 增至 417 PCs。
- libmicrodns 前期快速触达 `SRV/TXT/A/AAAA` 的读写函数，后续 PC 覆盖稳定在 147，说明现有种子能够进入核心 RR 解析路径，但更深路径可能需要更多结构化 DNS 种子。

## 4. 静态分析结果

| 项目 | scan-build 结果 | 报告目录 |
|---|---:|---|
| cJSON | 0 个告警 | `build/scan-report/cjson` |
| zlib | 3 个告警 | `build/scan-report/zlib/2026-05-29-195032-79272-1/index.html` |
| libmicrodns | 1 组告警 | `build/scan-report/libmicrodns/2026-05-29-195029-78663-1/index.html` |

### zlib 告警

scan-build 报告两处除零风险和一处 dead store：

- `gzwrite.c:303`：`gz_write(state, buf, len) / size`
- `gzread.c:464`：`gz_read(state, buf, len) / size`
- `gzwrite.c:480`：`ret = gz_vacate(state)` 后 `ret` 未被读取

初步判断：两处除零告警值得人工复核。代码在计算 `len = nitems * size` 后，只检查了 `if (size && len / size != nitems)`，最后执行 `return len ? ... / size : 0`。如果 `size == 0 && nitems > 0`，`len == 0`，返回 0，不会除零；如果 `size == 0`，`len` 恒为 0。因此这两处更像分析器未完整关联乘法结果与三目分支的误报。dead store 低优先级，属于返回值只用于触发副作用后的未读变量。

### libmicrodns 告警

scan-build 在 `mdns.c:436` 报告 `ifaddrs`、`mcast_addrs`、`mdns_ips` 潜在泄漏。对应路径是 `mdns_list_interfaces` 成功分配若干数组后，若 `ctx->nb_conns == 0`，函数只调用 `freeaddrinfo(res)` 就返回 `MDNS_NETERR`，没有释放上述三个数组。

这条告警看起来比 zlib 的告警更可疑，建议后续人工复现 `mdns_init` 中 `ctx->nb_conns == 0` 的路径，确认 `mdns_list_interfaces` 在该路径上是否确实可能分配非空数组。

## 5. 结论

10 分钟烟雾测试没有发现动态崩溃。当前三个项目的后续优先级建议：

1. libmicrodns：优先扩充 DNS/mDNS 结构化种子，尤其是 name compression、SRV、TXT、多 answer、多 additional record。
2. zlib：可以继续跑更长时间，但更建议扩展 driver，覆盖 `deflate`、`gz*` 文件 API、preset dictionary 等接口。
3. cJSON：当前 driver 已经很快进入平台期，若要提高价值，应加入 `cJSON_Utils` 的 patch / pointer / merge API。
