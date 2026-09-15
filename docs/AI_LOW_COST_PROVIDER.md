# 低成本模型接入与使用

服务由用户于2026-09-16指定：[code.viwo50when4.xyz](https://code.viwo50when4.xyz)。用于开发文本协作，游戏运行与正式测试不依赖此服务。任务分工见[开发手册](AI_AGENT_PLAYBOOK.md)。

## 已核实与未核实

- 官网返回New API页面；同源 `GET /v1/models` 使用本机密钥成功返回11个模型ID。公开 `GET /api/pricing` 返回倍率、分组及部分阶梯计费表达式。
- 模型列表包含 `deepseek-v4-flash-0731`、`deepseek-v4-flash`、`poolside/laguna-xs-2.1`、`gpt-5.6-luna` 等；这些是网关返回的名称，不是对底层模型身份、稳定性或官方价格的认证。
- 按用户补充，比较 `kimi-k3`、`gpt-5.6-luna`、`Agents-A1`、`deepseek-v4-flash-0731`，当前首选 `gpt-5.6-luna`。账户分组实际价格、余额、服务隐私条款和代码任务长期通过率未核实；不承诺最便宜或固定节约比例。
- 接口、模型、分组可能变化。不可用时停止该次请求，核对错误类别后再决定换模型；不自动轮询全部模型或充值。

## 本机运行

Python 3.10以上，无第三方包。工具只读取显式指定的UTF-8文本，不扫描仓库、不调用shell、不应用返回补丁。将精简任务包保存到被Git忽略的 `artifacts/delegation-input/`，检查没有密钥、个人信息或无关数据后执行：

```powershell
python tools/ask_low_cost_ai.py --key-file '<本机密钥文件绝对路径>' --prompt artifacts/delegation-input/task.txt --model gpt-5.6-luna --run-id WS-EXAMPLE-review-01 --max-tokens 1600
```

`--key-file`只接受文件路径，密钥值不能放命令参数。当前用户指定路径由本机会话持有，不把凭据文件复制到仓库。迁移机器时重新提供本地路径。

本机已在Git忽略的 `artifacts/delegation/provider-local.json` 保存密钥文件路径与首选模型（没有密钥值），供后续本地代理接手。实际任务创建prompt后可直接使用：

```powershell
$providerSettings = Get-Content artifacts/delegation/provider-local.json -Raw | ConvertFrom-Json
python tools/ask_low_cost_ai.py --key-file $providerSettings.key_file --prompt artifacts/delegation-input/task.txt --model $providerSettings.preferred_model --run-id WS-EXAMPLE-review-02 --max-tokens 1600
```

此文件不随Git迁移。新机器缺少它时，由操作者创建本地配置并放好密钥，不在提交中补入凭据。

输出到 `artifacts/delegation/<run-id>/response.md` 与 `receipt.json`。工具不在控制台打印回复正文；读取前将其视为待审建议。receipt包含输入哈希、字符数、请求模型、usage、次数、耗时和结束原因，不存密钥、请求头或完整提示词。原输入文件自行留在本机以便复核。

- 单次调用，默认输出上限1024，允许1–4096；输入1–16000字符，响应最多1MiB，网络操作超时60秒，无自动重试。字符限额不是精确token计数；输出上限与实际费用以服务计费为准。
- 固定同源HTTPS地址，拒绝HTTP重定向，不把Authorization转交其他域。没有自动工具调用、下载或执行能力。
- 同一run-id已存在就拒绝调用，包括前次失败；人工确认需重试时创建新attempt ID，保留失败证据。超时不代表未扣费。
- 退出0只表示收到正常结束的文本；退出2表示截断或非标准结束，需要审查；退出1为本地/API错误。三者都不代表代码验收通过。
- 401/403核对密钥或模型权限；429核对限流/额度；5xx或超时先记录，禁止无上限重试。错误仅记录类型和HTTP状态，不打印服务错误原文。
- 输出仅对当前密钥字面值做脱敏，并拒绝明显密钥输入；这不是通用秘密扫描器。发送前仍须人工/代理审查任务包。不要开启HTTP调试、PowerShell transcript或打印异常对象。

## 采用门槛

第一次只交一个L0样本，主代理核对结论是否有依据。之后可在已冻结契约下试L1，每类至少积累三个被接受样本再扩大；记录拒收率和主代理纠正成本。核心命令/存档/公平知识仍按L2审查，不能因价格低而只看最终摘要。

此工具是文本协作适配器，不会更改桌面应用的模型设置，也不会把网关模型注册为内置子代理。支持其他服务的客户端可直接使用同一委派模板，但凭据与权限由该客户端单独配置。

## 2026-09-16快速对比（SIMULATED）

四个模型使用相同1472字符任务、相同系统提示、1600输出上限和60秒网络操作超时；各一次，并发开始，无自动重试。任务包含4个预设缺陷（深层快照别名、队列引用、集合非确定排序、校验前覆写存档）和2个正确实现（合法记忆位置、手控原地自卫）。评分看六项判断、修复建议、反例与测试，而非回答长度。提示SHA-256 `d00cfe462635879d88dcbbe2108ccd0daa101d2285a430639e6508d967f57f8b`。

| 模型ID | 本次耗时 | 可用交付与质量 | 服务返回token |
|---|---:|---|---|
| `gpt-5.6-luna` | 27.605秒 | 正常JSON，六项判断全对，4缺陷全部命中、零误报；修复可行，建议测试未实际运行 | 输入648，输出1247，总1895 |
| `kimi-k3` | 44.632秒 | 响应未通过可用正文校验；不判定题目得分 | UNKNOWN |
| `Agents-A1` | 11.135秒 | 响应未通过可用正文校验；不判定题目得分 | UNKNOWN |
| `deepseek-v4-flash-0731` | 60.598秒 | 本次网络请求超时；不判定题目得分 | UNKNOWN |

原始请求文件在 `artifacts/delegation-input/model-comparison.txt`；回执及可用答案在 `artifacts/delegation/compare-20260916-1` 至 `-4`，对应表中调用顺序为Kimi、Luna、Agents、DeepSeek。失败可能与网关、模型输出格式、推理预算或网络有关，本轮未进一步定位。失败请求可能计费，不能按零成本记账。

选择：当前限制下Luna唯一按时完成并通过题目，作为L0/L1试用首选；另外三个暂不自动回退调用。这是单题服务可用性与审查质量筛选，不是模型综合能力排名，不证明GDScript实现、长任务、工具调用或真实项目验收能力。将来出现新任务需求再做对应样本，不为排名持续消耗token。公开价格页只证明服务宣称的计费规则，未核实实际账单，不给出货币成本比较。

离线检查（不计费）：

```powershell
python tests/tools/test_low_cost_ai.py
```
