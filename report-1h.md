# cJSON / zlib / libmicrodns 1 小时 fuzz 测试报告

## 1. 实验设置

本次对新增的三个项目继续运行 1 小时 libFuzzer + AddressSanitizer 测试：

- cJSON
- zlib
- libmicrodns

运行方式为并行执行三个 harness：

```bash
TIME=3600 ./harness/cjson/run.sh
TIME=3600 ./harness/zlib/run.sh
TIME=3600 ./harness/libmicrodns/run.sh
```

说明：本次 1 小时测试复用了上一轮 10 分钟 smoke test 后保留在 `build/corpus/<proj>` 中的 working corpus，因此属于“继续累计 fuzz”，不是从空 corpus 重新开始。

| 项目 | Driver | 1h 日志 |
|---|---|---|
| cJSON | `harness/cjson/fuzz_cjson.c` | `build/logs/cjson/fuzz-20260530-155512.log` |
| zlib | `harness/zlib/fuzz_zlib.c` | `build/logs/zlib/fuzz-20260530-155512.log` |
| libmicrodns | `harness/libmicrodns/fuzz_mdns.c` | `build/logs/libmicrodns/fuzz-20260530-155512.log` |

## 2. 动态测试结果

| 项目 | 运行时间 | 总执行 | 平均/末尾 exec/s | 最终 cov | 最终 ft | corpus | crash/OOM/timeout | findings |
|---|---:|---:|---:|---:|---:|---:|---|---:|
| cJSON | 3668s | 171,618,484 | 46,787 avg / 65,810 last | 302 | 1,878 | 528 | 0 / 0 / 0 | 0 |
| zlib | 3601s | 9,727,716 | 2,701 avg | 426 | 1,732 | 512 | 0 / 0 / 0 | 0 |
| libmicrodns | 3666s | 121,622,370 | 33,175 avg / 45,073 last | 147 | 693 | 243 | 0 / 0 / 0 | 0 |

三者均正常退出，未产生 `crash-*`、`oom-*`、`timeout-*` artifact。

## 3. 过程观察

### cJSON

cJSON 的执行速度最高，本轮 1 小时累计执行约 1.72 亿次。PC 覆盖率保持在 302，没有新增 PC 覆盖；features 从上一轮 1,849 增至 1,878，corpus 从 512 左右小幅增加到 528。说明当前 driver 对 parser / printer 主路径覆盖较稳定，但已经进入明显平台期。

后续如果继续做 cJSON，不建议只延长当前 driver 的运行时间。更有效的方向是扩展到 `cJSON_Utils`，覆盖 JSON Pointer、patch、merge、duplicate 等 API。

### zlib

zlib 本轮仍有有效覆盖增长：从 10 分钟测试时的 cov 417 继续增加到 426，features 增至 1,732。执行速度显著低于 cJSON 和 libmicrodns，主要原因是 driver 对每个输入都尝试 gzip/zlib wrapper 和 raw deflate 两种 inflate 模式，并且每条路径最多循环 256 次。

这说明 zlib 当前 driver 仍有继续运行价值。后续可以考虑加入 `deflate`、`inflateBack`、`gzread/gzwrite` 文件 API 或 preset dictionary 相关接口，扩大覆盖面。

### libmicrodns

libmicrodns 本轮执行约 1.22 亿次，PC 覆盖稳定在 147，features 从 678/693 附近小幅增长，corpus 到 243。现有种子已经能进入 SRV、TXT、A、AAAA 等 RR 读写路径，但 PC 覆盖长时间不变，说明现有输入结构对更深分支的触达有限。

后续提高效果的关键不是单纯延长时间，而是补充结构化 DNS/mDNS 种子：多 answer、多 additional record、name compression 环、异常 `rdlength`、SRV/TXT 边界长度、多个 question/answer section 组合。

## 4. 静态分析补充

沿用上一轮 scan-build 结果：

| 项目 | scan-build 结果 |
|---|---|
| cJSON | 0 个告警 |
| zlib | 3 个告警 |
| libmicrodns | 1 组告警 |

zlib 的两处除零告警位于 `gzwrite.c:303` 和 `gzread.c:464`，初步看更像分析器未能证明 `size == 0` 时 `len == 0`、三目表达式不会进入除法。另有一处 `gzwrite.c:480` dead store。

libmicrodns 的告警位于 `mdns.c:436`，涉及 `ctx->nb_conns == 0` 返回路径上 `ifaddrs`、`mcast_addrs`、`mdns_ips` 可能未释放。相比 zlib 告警，这条更值得后续人工复核。

## 5. 结论

1 小时动态测试未发现真实 crash、OOM 或 timeout。三个项目中，zlib 在 1 小时内仍有 PC 覆盖增长，继续跑 12 小时可能还能带来增量；cJSON 和 libmicrodns 当前 driver 已进入平台期，继续跑前更建议先扩展 API 覆盖或补充结构化种子。

若后续要做 12 小时实验，建议：

- cJSON：先扩展 `cJSON_Utils` driver，再跑 12h。
- zlib：当前 driver 可以直接累计跑 12h。
- libmicrodns：先增加结构化 DNS/mDNS seeds，再跑 12h。

## 6. 第二轮 1 小时追加测试

按相同方式继续复用 `build/corpus/<proj>` 中的 working corpus，又运行了一轮 1 小时：

```bash
TIME=3600 ./harness/cjson/run.sh
TIME=3600 ./harness/zlib/run.sh
TIME=3600 ./harness/libmicrodns/run.sh
```

| 项目 | 追加日志 | 运行时间 | 总执行 | 平均/末尾 exec/s | 最终 cov | 最终 ft | corpus | crash/OOM/timeout | findings |
|---|---|---:|---:|---:|---:|---:|---:|---|---:|
| cJSON | `build/logs/cjson/fuzz-20260530-182736.log` | 3665s | 218,519,363 | 59,623 avg / 72,545 last | 302 | 1,879 | 524 | 0 / 0 / 0 | 0 |
| zlib | `build/logs/zlib/fuzz-20260530-182736.log` | 3601s | 12,497,997 | 3,470 avg | 427 | 1,761 | 518 | 0 / 0 / 0 | 0 |
| libmicrodns | `build/logs/libmicrodns/fuzz-20260530-182736.log` | 3664s | 147,506,299 | 40,258 avg / 40,825 last | 147 | 697 | 245 | 0 / 0 / 0 | 0 |

第二轮仍未发现崩溃、OOM 或 timeout。追加运行后的 working corpus 文件数为：

| 项目 | `build/corpus/<proj>` 文件数 |
|---|---:|
| cJSON | 564 |
| zlib | 1,496 |
| libmicrodns | 259 |

### 第二轮观察

- cJSON：PC 覆盖仍停留在 302，仅 features 从 1,878 增到 1,879，说明当前 parser/printer driver 基本耗尽增量。
- zlib：PC 覆盖从上一轮 426 增至 427，features 从 1,732 增至 1,761，仍有少量有效增长。
- libmicrodns：PC 覆盖仍为 147，features 从 693 增至 697，主要是在已有 RR 解析路径上做细粒度输入变异。

累计两轮 1 小时后，最值得继续直接跑长时间的是 zlib；cJSON 和 libmicrodns 更适合先扩展 driver 或 seeds 后再投入 12 小时。

## 7. 第三轮 1 小时追加测试

继续复用同一 working corpus，又运行第三轮 1 小时：

| 项目 | 追加日志 | 运行时间 | 总执行 | 平均/末尾 exec/s | 最终 cov | 最终 ft | corpus | crash/OOM/timeout | findings |
|---|---|---:|---:|---:|---:|---:|---:|---|---:|
| cJSON | `build/logs/cjson/fuzz-20260530-193325.log` | 3666s | 174,127,946 | 47,498 avg / 53,507 last | 302 | 1,883 | 526 | 0 / 0 / 0 | 0 |
| zlib | `build/logs/zlib/fuzz-20260530-193325.log` | 3601s | 11,477,833 | 3,187 avg | 428 | 1,768 | 525 | 0 / 0 / 0 | 0 |
| libmicrodns | `build/logs/libmicrodns/fuzz-20260530-193325.log` | 3665s | 126,086,917 | 34,403 avg / 31,226 last | 147 | 701 | 246 | 0 / 0 / 0 | 0 |

第三轮结束后，仍未发现崩溃、OOM 或 timeout。追加运行后的 working corpus 文件数为：

| 项目 | `build/corpus/<proj>` 文件数 |
|---|---:|
| cJSON | 566 |
| zlib | 1,757 |
| libmicrodns | 261 |

### 三轮累计观察

- cJSON：三轮 1 小时后 PC 覆盖始终停留在 302，仅 features 从 1,878 增至 1,883，继续单纯延长当前 driver 收益很低。
- zlib：三轮中持续有小幅 PC 覆盖增长，第一轮 426，第二轮 427，第三轮 428，是三个新增项目里最值得继续直接累计运行的目标。
- libmicrodns：PC 覆盖始终为 147，但 features 从 693 增至 701，说明变异仍在已有路径里制造细粒度差异；想提高 PC 覆盖，应优先补充更复杂的 mDNS packet seeds。

截至第三轮追加测试，三个项目累计运行约 3 小时 10 分钟（含最初 10 分钟 smoke test），未产生任何 findings artifact。

## 8. 第四轮 8 小时追加测试

继续复用同一 working corpus，将三个目标并行运行约 8 小时：

```bash
TIME=28800 ./harness/cjson/run.sh
TIME=28800 ./harness/zlib/run.sh
TIME=28800 ./harness/libmicrodns/run.sh
```

| 项目 | 追加日志 | 运行时间 | 总执行 | 平均/末尾 exec/s | 最终 cov | 最终 ft | corpus | crash/OOM/timeout | findings |
|---|---|---:|---:|---:|---:|---:|---:|---|---:|
| cJSON | `build/logs/cjson/fuzz-20260530-232517.log` | 28953s | 2,080,696,433 | 71,865 avg / 80,650 last | 304 | 1,887 | 532 | 0 / 0 / 0 | 0 |
| zlib | `build/logs/zlib/fuzz-20260530-232517.log` | 28801s | 138,837,679 | 4,820 avg | 431 | 1,822 | 546 | 0 / 0 / 0 | 0 |
| libmicrodns | `build/logs/libmicrodns/fuzz-20260530-232517.log` | 28949s | 1,126,165,884 | 38,902 avg / 59,333 last | 147 | 710 | 251 | 0 / 0 / 0 | 0 |

8 小时追加运行后的 working corpus 文件数为：

| 项目 | `build/corpus/<proj>` 文件数 |
|---|---:|
| cJSON | 569 |
| zlib | 2,627 |
| libmicrodns | 267 |

### 8 小时观察

- cJSON：PC 覆盖从第三轮的 302 增至 304，features 从 1,883 增至 1,887，说明长时间运行仍能挖到少量边缘路径，但增量已经较低。
- zlib：PC 覆盖从 428 增至 431，features 从 1,768 增至 1,822，是本轮里增量最明显的目标，继续长跑仍有价值。
- libmicrodns：PC 覆盖仍为 147，features 从 701 增至 710，主要增量仍来自已有解析路径内的细粒度变异。

本轮 8 小时追加测试未发现 crash、OOM 或 timeout，`build/findings/cjson`、`build/findings/zlib`、`build/findings/libmicrodns` 中均未产生 findings 文件。测试结束后检查进程列表，未发现残留的 `fuzz_cjson`、`fuzz_zlib` 或 `fuzz_mdns` 进程。

## 9. 第五轮 1 小时追加测试

在 8 小时追加测试结束后的 working corpus 基础上，又继续运行 1 小时：

```bash
TIME=3600 ./harness/cjson/run.sh
TIME=3600 ./harness/zlib/run.sh
TIME=3600 ./harness/libmicrodns/run.sh
```

| 项目 | 追加日志 | 运行时间 | 总执行 | 平均/末尾 exec/s | 最终 cov | 最终 ft | corpus | crash/OOM/timeout | findings |
|---|---|---:|---:|---:|---:|---:|---:|---|---:|
| cJSON | `build/logs/cjson/fuzz-20260531-101559.log` | 3663s | 255,603,845 | 69,779 avg / 58,620 last | 304 | 1,887 | 528 | 0 / 0 / 0 | 0 |
| zlib | `build/logs/zlib/fuzz-20260531-101559.log` | 3601s | 12,937,745 | 3,592 avg | 431 | 1,825 | 551 | 0 / 0 / 0 | 0 |
| libmicrodns | `build/logs/libmicrodns/fuzz-20260531-101559.log` | 3663s | 161,984,041 | 44,221 avg / 43,575 last | 147 | 710 | 251 | 0 / 0 / 0 | 0 |

本轮追加运行后的 working corpus 文件数为：

| 项目 | `build/corpus/<proj>` 文件数 |
|---|---:|
| cJSON | 569 |
| zlib | 2,740 |
| libmicrodns | 267 |

### 第五轮观察

- cJSON：覆盖和 features 均未增长，仍为 cov 304、ft 1,887。
- zlib：PC 覆盖未增长，features 从 1,822 增至 1,825，working corpus 文件数继续增加，是本轮唯一还有明显语料增量的目标。
- libmicrodns：覆盖和 features 均未增长，仍为 cov 147、ft 710。

本轮 1 小时追加测试仍未发现 crash、OOM 或 timeout，三个 findings 目录均为空。测试结束后检查进程列表，未发现残留的 `fuzz_cjson`、`fuzz_zlib` 或 `fuzz_mdns` 进程。
