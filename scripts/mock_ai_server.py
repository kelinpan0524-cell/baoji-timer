#!/usr/bin/env python3
"""本地 mock AI 服务器：模拟 OpenAI 兼容 /chat/completions 接口。

用途：没有真实 AI Key 时，端到端验证 App 的"AI 拆解/自然语言生成计划"链路。

用法：
  python3 scripts/mock_ai_server.py [端口，默认 8765]

App 侧配置：
  设置 → AI 配置 → Base URL 填 http://<电脑局域网IP>:8765/v1
  （模拟器里电脑地址是 http://10.0.2.2:8765/v1；API Key 随便填；模型名随便填）

真实 AI 的返回直接改本文件里的 PLAN_JSON（描述生成）/ PARSED_JSON（原文导入）。
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

# 描述生成模式返回的计划（3 练：背/胸/腿）
PLAN_JSON = [
    {
        "weekday": 1,
        "title": "背部日",
        "exercises": [
            {"name": "杠铃硬拉", "sets": 3, "reps_min": 5, "reps_max": 8,
             "rest_sec": 180, "kind": "compound", "main_muscle": "背"},
            {"name": "引体向上", "sets": 3, "reps_min": 6, "reps_max": 10,
             "rest_sec": 150, "kind": "compound", "main_muscle": "背"},
            {"name": "坐姿划船", "sets": 3, "reps_min": 8, "reps_max": 12,
             "rest_sec": 90, "kind": "assistance", "main_muscle": "背"},
        ],
    },
    {
        "weekday": 3,
        "title": "胸部日",
        "exercises": [
            {"name": "杠铃卧推", "sets": 4, "reps_min": 5, "reps_max": 8,
             "rest_sec": 180, "kind": "compound", "main_muscle": "胸"},
            {"name": "上斜哑铃卧推", "sets": 3, "reps_min": 8, "reps_max": 12,
             "rest_sec": 120, "kind": "compound", "main_muscle": "胸"},
        ],
    },
    {
        "weekday": 5,
        "title": "腿部日",
        "exercises": [
            {"name": "杠铃深蹲", "sets": 4, "reps_min": 5, "reps_max": 8,
             "rest_sec": 180, "kind": "compound", "main_muscle": "腿"},
            {"name": "罗马尼亚硬拉", "sets": 3, "reps_min": 8, "reps_max": 10,
             "rest_sec": 150, "kind": "compound", "main_muscle": "腿"},
        ],
    },
]


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path.endswith("/chat/completions"):
            content = json.dumps(PLAN_JSON, ensure_ascii=False)
            body = json.dumps({
                "id": "mock",
                "object": "chat.completion",
                "choices": [{
                    "index": 0,
                    "message": {"role": "assistant", "content": content},
                    "finish_reason": "stop",
                }],
            }).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *_args):
        pass  # 静默


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    print(f"mock AI server: http://0.0.0.0:{port}/v1/chat/completions")
    HTTPServer(("0.0.0.0", port), Handler).serve_forever()
