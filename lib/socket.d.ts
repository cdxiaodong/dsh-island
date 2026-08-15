/**
 * CodeIsland 的 Unix socket 客户端。
 *
 * CodeIsland 通过 `/tmp/codeisland-<uid>.sock` 接收所有 AI 工具的 hook 事件：
 * 客户端 connect → 写入一帧 JSON → half-close（EOF 触发服务端处理）。
 *
 * - 非阻塞事件：服务端处理完立即回写 `{}` 并关闭连接。
 * - 阻塞事件（PermissionRequest / Notification 带 question）：服务端保持
 *   连接，直到用户在刘海面板上批准/拒绝后才回写
 *   `{"hookSpecificOutput":{...,"decision":{"behavior":"allow|deny"}}}`。
 */
export declare class CodeIslandSocket {
    readonly socketPath: string;
    readonly connectTimeoutMs: number;
    constructor(socketPath?: string, connectTimeoutMs?: number);
    /** CodeIsland 应用是否在运行（socket 文件存在且为 Unix socket）。 */
    available(): boolean;
    /**
     * 发送一帧事件。
     *
     * @param payload  事件 JSON（会被 `JSON.stringify` 后整帧写入）。
     * @param opts.wait  阻塞事件置 true —— 等待 CodeIsland 回写决策。
     * @param opts.timeoutMs  阻塞等待超时（毫秒）。非阻塞事件用 connectTimeoutMs。
     * @returns `{ ok, response?, error? }`；response 为服务端回写的 JSON。
     */
    send(payload: Record<string, unknown>, opts?: {
        wait?: boolean;
        timeoutMs?: number;
    }): Promise<SendResult>;
}
/** CodeIsland socket 默认路径：/tmp/codeisland-<uid>.sock（可用环境变量覆盖）。 */
export declare function defaultSocketPath(): string;
export interface SendResult {
    ok: boolean;
    /** 服务端回写并成功解析的 JSON（阻塞事件为决策 payload）。 */
    response?: Record<string, unknown>;
    /** 失败原因（连接错误 / 超时 / 无法解析）。 */
    error?: string;
}
/**
 * 从 CodeIsland 的 PermissionRequest 响应里解析决策。
 * 兼容两种回写形态：
 *   `{"hookSpecificOutput":{"decision":{"behavior":"allow"}}}`  （标准）
 *   `{"decision":{"behavior":"always"}}`                          （宽松）
 *
 * @returns 'allow' | 'deny' | null（无有效决策）
 */
export declare function parseDecision(response: Record<string, unknown> | undefined): 'allow' | 'deny' | null;
//# sourceMappingURL=socket.d.ts.map