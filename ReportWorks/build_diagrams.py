#!/usr/bin/env python3
import os
import subprocess

img_dir = '/home/chessplayer/DEV/Pascal/ReportWorks/images'
os.makedirs(img_dir, exist_ok=True)

def generate_svgs():
    # -------------------------------------------------------------
    # 1. METRICS FORMULAS (UA & EN)
    # -------------------------------------------------------------
    svg_metrics_ua = '''<svg width="700" height="75" viewBox="0 0 700 75" xmlns="http://www.w3.org/2000/svg">
  <rect width="700" height="75" rx="6" fill="#f8fafc" stroke="#cbd5e1" stroke-width="1.5" />
  <rect x="0" y="0" width="6" height="75" rx="3" fill="#2563eb" />
  
  <!-- Metric 1: Throughput -->
  <text x="20" y="24" font-family="DejaVu Sans, Arial" font-size="11" font-weight="bold" fill="#1e3a8a">1. Пропускна здатність</text>
  <text x="20" y="52" font-family="DejaVu Serif, Georgia" font-size="13" font-style="italic" fill="#0f172a">Throughput = N_ops / T_wall</text>
  <text x="20" y="66" font-family="DejaVu Sans, Arial" font-size="9" fill="#64748b">[операцій/сек, tx/s, cell/s]</text>

  <line x1="260" y1="10" x2="260" y2="65" stroke="#cbd5e1" stroke-width="1" />

  <!-- Metric 2: Ratio -->
  <text x="280" y="24" font-family="DejaVu Sans, Arial" font-size="11" font-weight="bold" fill="#1e3a8a">2. Коефіцієнт ядра ОС</text>
  <text x="280" y="52" font-family="DejaVu Serif, Georgia" font-size="13" font-style="italic" fill="#0f172a">R_cpu = T_user / T_system</text>
  <text x="280" y="66" font-family="DejaVu Sans, Arial" font-size="9" fill="#059669">(вище = менше блокувань futex)</text>

  <line x1="495" y1="10" x2="495" y2="65" stroke="#cbd5e1" stroke-width="1" />

  <!-- Metric 3: Parallel Efficiency -->
  <text x="515" y="24" font-family="DejaVu Sans, Arial" font-size="11" font-weight="bold" fill="#1e3a8a">3. ККД паралелізму</text>
  <text x="515" y="52" font-family="DejaVu Serif, Georgia" font-size="12.5" font-style="italic" fill="#0f172a">η = T_user / (T_wall × 12)</text>
  <text x="515" y="66" font-family="DejaVu Sans, Arial" font-size="9" fill="#0284c7">Утилізація 12 ядер CPU (%)</text>
</svg>'''

    svg_metrics_en = '''<svg width="700" height="75" viewBox="0 0 700 75" xmlns="http://www.w3.org/2000/svg">
  <rect width="700" height="75" rx="6" fill="#f8fafc" stroke="#cbd5e1" stroke-width="1.5" />
  <rect x="0" y="0" width="6" height="75" rx="3" fill="#2563eb" />
  
  <text x="20" y="24" font-family="DejaVu Sans, Arial" font-size="11" font-weight="bold" fill="#1e3a8a">1. System Throughput</text>
  <text x="20" y="52" font-family="DejaVu Serif, Georgia" font-size="13" font-style="italic" fill="#0f172a">Throughput = N_ops / T_wall</text>
  <text x="20" y="66" font-family="DejaVu Sans, Arial" font-size="9" fill="#64748b">[operations/sec, tx/s, cell/s]</text>

  <line x1="260" y1="10" x2="260" y2="65" stroke="#cbd5e1" stroke-width="1" />

  <text x="280" y="24" font-family="DejaVu Sans, Arial" font-size="11" font-weight="bold" fill="#1e3a8a">2. Kernel Overhead Ratio</text>
  <text x="280" y="52" font-family="DejaVu Serif, Georgia" font-size="13" font-style="italic" fill="#0f172a">R_cpu = T_user / T_system</text>
  <text x="280" y="66" font-family="DejaVu Sans, Arial" font-size="9" fill="#059669">(higher = fewer futex stalls)</text>

  <line x1="495" y1="10" x2="495" y2="65" stroke="#cbd5e1" stroke-width="1" />

  <text x="515" y="24" font-family="DejaVu Sans, Arial" font-size="11" font-weight="bold" fill="#1e3a8a">3. Parallel Efficiency</text>
  <text x="515" y="52" font-family="DejaVu Serif, Georgia" font-size="12.5" font-style="italic" fill="#0f172a">η = T_user / (T_wall × 12)</text>
  <text x="515" y="66" font-family="DejaVu Sans, Arial" font-size="9" fill="#0284c7">12 CPU Cores Scaling (%)</text>
</svg>'''

    # -------------------------------------------------------------
    # 2. SCHEME TEST 1: Crushing In-Memory Cache (UA & EN)
    # -------------------------------------------------------------
    svg_test1_ua = '''<svg width="700" height="90" viewBox="0 0 700 90" xmlns="http://www.w3.org/2000/svg">
  <rect width="700" height="90" rx="6" fill="#f8fafc" stroke="#cbd5e1" stroke-width="1.5" />
  <rect x="0" y="0" width="6" height="90" rx="3" fill="#0284c7" />

  <rect x="15" y="12" width="135" height="66" rx="5" fill="#eff6ff" stroke="#3b82f6" stroke-width="1.5" />
  <text x="82" y="32" font-family="DejaVu Sans, Arial" font-size="10.5" font-weight="bold" fill="#1e3a8a" text-anchor="middle">12 CPU Workers</text>
  <text x="82" y="49" font-family="DejaVu Sans, Arial" font-size="8.5" fill="#0369a1" text-anchor="middle">90% Читання (1.8M ops)</text>
  <text x="82" y="64" font-family="DejaVu Sans, Arial" font-size="8.5" fill="#dc2626" text-anchor="middle">10% Оновлення (200k)</text>

  <line x1="150" y1="33" x2="205" y2="33" stroke="#0284c7" stroke-width="1.5" stroke-dasharray="3,2" />
  <polygon points="205,30 212,33 205,36" fill="#0284c7" />
  <text x="178" y="27" font-family="DejaVu Sans, Arial" font-size="8" fill="#0284c7" text-anchor="middle">Read Lock</text>

  <line x1="150" y1="58" x2="205" y2="58" stroke="#dc2626" stroke-width="1.5" />
  <polygon points="205,55 212,58 205,61" fill="#dc2626" />
  <text x="178" y="70" font-family="DejaVu Sans, Arial" font-size="8" fill="#dc2626" text-anchor="middle">Write Lock</text>

  <rect x="215" y="10" width="265" height="70" rx="5" fill="#ffffff" stroke="#0284c7" stroke-width="1.5" />
  <text x="347" y="27" font-family="DejaVu Sans, Arial" font-size="10" font-weight="bold" fill="#0369a1" text-anchor="middle">Order Book Cache + TSlimRWLock</text>
  <text x="347" y="43" font-family="DejaVu Sans, Arial" font-size="8" fill="#475569" text-anchor="middle">Паралельні читачі на регістрах CPU (0 syscalls)</text>
  <line x1="225" y1="49" x2="470" y2="49" stroke="#e2e8f0" stroke-width="1" />
  <text x="347" y="67" font-family="DejaVu Serif, Georgia" font-size="9" font-style="italic" fill="#0f172a" text-anchor="middle">RiskHash = (H_prev × 31 + Price) ⊕ (H_prev &gt;&gt; 3)</text>

  <line x1="480" y1="45" x2="525" y2="45" stroke="#16a34a" stroke-width="2" />
  <polygon points="525,41 533,45 525,49" fill="#16a34a" />
  <text x="502" y="38" font-family="DejaVu Sans, Arial" font-size="8" fill="#16a34a" text-anchor="middle">TChannel</text>

  <rect x="535" y="12" width="150" height="66" rx="5" fill="#f0fdf4" stroke="#16a34a" stroke-width="1.5" />
  <text x="610" y="32" font-family="DejaVu Sans, Arial" font-size="10.5" font-weight="bold" fill="#14532d" text-anchor="middle">Потоковий аудит</text>
  <text x="610" y="49" font-family="DejaVu Sans, Arial" font-size="8.5" fill="#16a34a" text-anchor="middle">200 000 оновлень</text>
  <text x="610" y="64" font-family="DejaVu Sans, Arial" font-size="8" fill="#64748b" text-anchor="middle">Backpressure черга</text>
</svg>'''

    svg_test1_en = '''<svg width="700" height="90" viewBox="0 0 700 90" xmlns="http://www.w3.org/2000/svg">
  <rect width="700" height="90" rx="6" fill="#f8fafc" stroke="#cbd5e1" stroke-width="1.5" />
  <rect x="0" y="0" width="6" height="90" rx="3" fill="#0284c7" />

  <rect x="15" y="12" width="135" height="66" rx="5" fill="#eff6ff" stroke="#3b82f6" stroke-width="1.5" />
  <text x="82" y="32" font-family="DejaVu Sans, Arial" font-size="10.5" font-weight="bold" fill="#1e3a8a" text-anchor="middle">12 CPU Workers</text>
  <text x="82" y="49" font-family="DejaVu Sans, Arial" font-size="8.5" fill="#0369a1" text-anchor="middle">90% Reads (1.8M ops)</text>
  <text x="82" y="64" font-family="DejaVu Sans, Arial" font-size="8.5" fill="#dc2626" text-anchor="middle">10% Updates (200k)</text>

  <line x1="150" y1="33" x2="205" y2="33" stroke="#0284c7" stroke-width="1.5" stroke-dasharray="3,2" />
  <polygon points="205,30 212,33 205,36" fill="#0284c7" />
  <text x="178" y="27" font-family="DejaVu Sans, Arial" font-size="8" fill="#0284c7" text-anchor="middle">Read Lock</text>

  <line x1="150" y1="58" x2="205" y2="58" stroke="#dc2626" stroke-width="1.5" />
  <polygon points="205,55 212,58 205,61" fill="#dc2626" />
  <text x="178" y="70" font-family="DejaVu Sans, Arial" font-size="8" fill="#dc2626" text-anchor="middle">Write Lock</text>

  <rect x="215" y="10" width="265" height="70" rx="5" fill="#ffffff" stroke="#0284c7" stroke-width="1.5" />
  <text x="347" y="27" font-family="DejaVu Sans, Arial" font-size="10" font-weight="bold" fill="#0369a1" text-anchor="middle">Order Book Cache + TSlimRWLock</text>
  <text x="347" y="43" font-family="DejaVu Sans, Arial" font-size="8" fill="#475569" text-anchor="middle">Parallel readers on CPU registers (0 syscalls)</text>
  <line x1="225" y1="49" x2="470" y2="49" stroke="#e2e8f0" stroke-width="1" />
  <text x="347" y="67" font-family="DejaVu Serif, Georgia" font-size="9" font-style="italic" fill="#0f172a" text-anchor="middle">RiskHash = (H_prev × 31 + Price) ⊕ (H_prev &gt;&gt; 3)</text>

  <line x1="480" y1="45" x2="525" y2="45" stroke="#16a34a" stroke-width="2" />
  <polygon points="525,41 533,45 525,49" fill="#16a34a" />
  <text x="502" y="38" font-family="DejaVu Sans, Arial" font-size="8" fill="#16a34a" text-anchor="middle">TChannel</text>

  <rect x="535" y="12" width="150" height="66" rx="5" fill="#f0fdf4" stroke="#16a34a" stroke-width="1.5" />
  <text x="610" y="32" font-family="DejaVu Sans, Arial" font-size="10.5" font-weight="bold" fill="#14532d" text-anchor="middle">Streaming Audit</text>
  <text x="610" y="49" font-family="DejaVu Sans, Arial" font-size="8.5" fill="#16a34a" text-anchor="middle">200,000 Event Stream</text>
  <text x="610" y="64" font-family="DejaVu Sans, Arial" font-size="8" fill="#64748b" text-anchor="middle">Backpressure Queue</text>
</svg>'''

    # -------------------------------------------------------------
    # 3. SCHEME TEST 2: Pipeline (UA & EN)
    # -------------------------------------------------------------
    svg_test2_ua = '''<svg width="700" height="80" viewBox="0 0 700 80" xmlns="http://www.w3.org/2000/svg">
  <rect width="700" height="80" rx="6" fill="#f8fafc" stroke="#cbd5e1" stroke-width="1.5" />
  <rect x="0" y="0" width="6" height="80" rx="3" fill="#16a34a" />

  <rect x="15" y="10" width="130" height="60" rx="5" fill="#eff6ff" stroke="#3b82f6" stroke-width="1.5" />
  <text x="80" y="33" font-family="DejaVu Sans, Arial" font-size="10" font-weight="bold" fill="#1e3a8a" text-anchor="middle">6 Генераторів</text>
  <text x="80" y="48" font-family="DejaVu Sans, Arial" font-size="8.5" fill="#2563eb" text-anchor="middle">Multi-Producer</text>
  <text x="80" y="62" font-family="DejaVu Sans, Arial" font-size="8" fill="#64748b" text-anchor="middle">1M транзакцій</text>

  <line x1="145" y1="40" x2="185" y2="40" stroke="#2563eb" stroke-width="2" />
  <polygon points="185,36 193,40 185,44" fill="#2563eb" />

  <rect x="195" y="10" width="140" height="60" rx="5" fill="#f0fdf4" stroke="#16a34a" stroke-width="1.5" />
  <text x="265" y="33" font-family="DejaVu Sans, Arial" font-size="10" font-weight="bold" fill="#14532d" text-anchor="middle">Inbound Channel</text>
  <text x="265" y="48" font-family="DejaVu Sans, Arial" font-size="8.5" fill="#16a34a" text-anchor="middle">generic TChannel&lt;TTx&gt;</text>
  <text x="265" y="62" font-family="DejaVu Sans, Arial" font-size="8" fill="#64748b" text-anchor="middle">Zero-Alloc (Cap: 4096)</text>

  <line x1="335" y1="40" x2="375" y2="40" stroke="#2563eb" stroke-width="2" />
  <polygon points="375,36 383,40 375,44" fill="#2563eb" />

  <rect x="385" y="10" width="130" height="60" rx="5" fill="#eff6ff" stroke="#3b82f6" stroke-width="1.5" />
  <text x="450" y="33" font-family="DejaVu Sans, Arial" font-size="10" font-weight="bold" fill="#1e3a8a" text-anchor="middle">6 Воркерів</text>
  <text x="450" y="48" font-family="DejaVu Sans, Arial" font-size="8.5" fill="#2563eb" text-anchor="middle">Multi-Consumer</text>
  <text x="450" y="62" font-family="DejaVu Sans, Arial" font-size="8" fill="#64748b" text-anchor="middle">Комісії + верифікація</text>

  <line x1="515" y1="40" x2="550" y2="40" stroke="#2563eb" stroke-width="2" />
  <polygon points="550,36 558,40 550,44" fill="#2563eb" />

  <rect x="560" y="10" width="125" height="60" rx="5" fill="#fefce8" stroke="#ca8a04" stroke-width="1.5" />
  <text x="622" y="33" font-family="DejaVu Sans, Arial" font-size="10" font-weight="bold" fill="#713f12" text-anchor="middle">Outbound &amp; Аудит</text>
  <text x="622" y="48" font-family="DejaVu Sans, Arial" font-size="8.5" fill="#ca8a04" text-anchor="middle">TChannel → 1 Auditor</text>
  <text x="622" y="62" font-family="DejaVu Sans, Arial" font-size="8" fill="#64748b" text-anchor="middle">Фінальний баланс</text>
</svg>'''

    svg_test2_en = '''<svg width="700" height="80" viewBox="0 0 700 80" xmlns="http://www.w3.org/2000/svg">
  <rect width="700" height="80" rx="6" fill="#f8fafc" stroke="#cbd5e1" stroke-width="1.5" />
  <rect x="0" y="0" width="6" height="80" rx="3" fill="#16a34a" />

  <rect x="15" y="10" width="130" height="60" rx="5" fill="#eff6ff" stroke="#3b82f6" stroke-width="1.5" />
  <text x="80" y="33" font-family="DejaVu Sans, Arial" font-size="10" font-weight="bold" fill="#1e3a8a" text-anchor="middle">6 Producers</text>
  <text x="80" y="48" font-family="DejaVu Sans, Arial" font-size="8.5" fill="#2563eb" text-anchor="middle">Multi-Producer</text>
  <text x="80" y="62" font-family="DejaVu Sans, Arial" font-size="8" fill="#64748b" text-anchor="middle">1M Transactions</text>

  <line x1="145" y1="40" x2="185" y2="40" stroke="#2563eb" stroke-width="2" />
  <polygon points="185,36 193,40 185,44" fill="#2563eb" />

  <rect x="195" y="10" width="140" height="60" rx="5" fill="#f0fdf4" stroke="#16a34a" stroke-width="1.5" />
  <text x="265" y="33" font-family="DejaVu Sans, Arial" font-size="10" font-weight="bold" fill="#14532d" text-anchor="middle">Inbound Channel</text>
  <text x="265" y="48" font-family="DejaVu Sans, Arial" font-size="8.5" fill="#16a34a" text-anchor="middle">generic TChannel&lt;TTx&gt;</text>
  <text x="265" y="62" font-family="DejaVu Sans, Arial" font-size="8" fill="#64748b" text-anchor="middle">Zero-Alloc (Cap: 4096)</text>

  <line x1="335" y1="40" x2="375" y2="40" stroke="#2563eb" stroke-width="2" />
  <polygon points="375,36 383,40 375,44" fill="#2563eb" />

  <rect x="385" y="10" width="130" height="60" rx="5" fill="#eff6ff" stroke="#3b82f6" stroke-width="1.5" />
  <text x="450" y="33" font-family="DejaVu Sans, Arial" font-size="10" font-weight="bold" fill="#1e3a8a" text-anchor="middle">6 Workers</text>
  <text x="450" y="48" font-family="DejaVu Sans, Arial" font-size="8.5" fill="#2563eb" text-anchor="middle">Multi-Consumer</text>
  <text x="450" y="62" font-family="DejaVu Sans, Arial" font-size="8" fill="#64748b" text-anchor="middle">Fees + Validation</text>

  <line x1="515" y1="40" x2="550" y2="40" stroke="#2563eb" stroke-width="2" />
  <polygon points="550,36 558,40 550,44" fill="#2563eb" />

  <rect x="560" y="10" width="125" height="60" rx="5" fill="#fefce8" stroke="#ca8a04" stroke-width="1.5" />
  <text x="622" y="33" font-family="DejaVu Sans, Arial" font-size="10" font-weight="bold" fill="#713f12" text-anchor="middle">Outbound &amp; Audit</text>
  <text x="622" y="48" font-family="DejaVu Sans, Arial" font-size="8.5" fill="#ca8a04" text-anchor="middle">TChannel → 1 Auditor</text>
  <text x="622" y="62" font-family="DejaVu Sans, Arial" font-size="8" fill="#64748b" text-anchor="middle">Final Ledger Audit</text>
</svg>'''

    # -------------------------------------------------------------
    # 4. SCHEME TEST 3: DAG Actor Graph (UA & EN)
    # -------------------------------------------------------------
    svg_test3_ua = '''<svg width="700" height="85" viewBox="0 0 700 85" xmlns="http://www.w3.org/2000/svg">
  <rect width="700" height="85" rx="6" fill="#f8fafc" stroke="#cbd5e1" stroke-width="1.5" />
  <rect x="0" y="0" width="6" height="85" rx="3" fill="#7c3aed" />

  <rect x="15" y="12" width="105" height="60" rx="5" fill="#eff6ff" stroke="#3b82f6" stroke-width="1.5" />
  <text x="67" y="36" font-family="DejaVu Sans, Arial" font-size="10" font-weight="bold" fill="#1e3a8a" text-anchor="middle">4 Ingest</text>
  <text x="67" y="52" font-family="DejaVu Sans, Arial" font-size="8.5" fill="#2563eb" text-anchor="middle">Producers (2M)</text>

  <line x1="120" y1="42" x2="155" y2="42" stroke="#7c3aed" stroke-width="2" />
  <polygon points="155,38 163,42 155,46" fill="#7c3aed" />

  <rect x="165" y="12" width="115" height="60" rx="5" fill="#f5f3ff" stroke="#7c3aed" stroke-width="1.5" />
  <text x="222" y="32" font-family="DejaVu Sans, Arial" font-size="10" font-weight="bold" fill="#5b21b6" text-anchor="middle">Router Actor</text>
  <text x="222" y="47" font-family="DejaVu Sans, Arial" font-size="8" fill="#7c3aed" text-anchor="middle">Partition Key:</text>
  <text x="222" y="61" font-family="monospace" font-size="8.5" fill="#5b21b6" text-anchor="middle">Shard = ID mod 4</text>

  <line x1="280" y1="28" x2="320" y2="20" stroke="#7c3aed" stroke-width="1.5" />
  <polygon points="320,17 328,19 322,23" fill="#7c3aed" />
  <line x1="280" y1="56" x2="320" y2="64" stroke="#7c3aed" stroke-width="1.5" />
  <polygon points="322,61 328,65 320,67" fill="#7c3aed" />

  <rect x="330" y="8" width="185" height="68" rx="5" fill="#ffffff" stroke="#7c3aed" stroke-width="1.5" />
  <text x="422" y="24" font-family="DejaVu Sans, Arial" font-size="9" font-weight="bold" fill="#5b21b6" text-anchor="middle">4 Shard Channels &amp; Workers</text>
  <text x="422" y="39" font-family="DejaVu Sans, Arial" font-size="7.5" fill="#334155" text-anchor="middle">Shard_0 • Shard_1 • Shard_2 • Shard_3</text>
  <text x="422" y="53" font-family="DejaVu Sans, Arial" font-size="7.5" fill="#059669" text-anchor="middle">Паралельний розрахунок контрольних сум</text>
  <text x="422" y="67" font-family="DejaVu Serif, Georgia" font-size="8" font-style="italic" fill="#0f172a" text-anchor="middle">CRC_total = CRC_0 + CRC_1 + CRC_2 + CRC_3</text>

  <line x1="515" y1="42" x2="550" y2="42" stroke="#7c3aed" stroke-width="2" />
  <polygon points="550,38 558,42 550,46" fill="#7c3aed" />

  <rect x="560" y="12" width="125" height="60" rx="5" fill="#f0fdf4" stroke="#16a34a" stroke-width="1.5" />
  <text x="622" y="32" font-family="DejaVu Sans, Arial" font-size="10" font-weight="bold" fill="#14532d" text-anchor="middle">Aggregator</text>
  <text x="622" y="47" font-family="DejaVu Sans, Arial" font-size="8.5" fill="#16a34a" text-anchor="middle">Fan-In Зведення</text>
  <text x="622" y="61" font-family="DejaVu Sans, Arial" font-size="8" fill="#64748b" text-anchor="middle">8M передач сумарно</text>
</svg>'''

    svg_test3_en = '''<svg width="700" height="85" viewBox="0 0 700 85" xmlns="http://www.w3.org/2000/svg">
  <rect width="700" height="85" rx="6" fill="#f8fafc" stroke="#cbd5e1" stroke-width="1.5" />
  <rect x="0" y="0" width="6" height="85" rx="3" fill="#7c3aed" />

  <rect x="15" y="12" width="105" height="60" rx="5" fill="#eff6ff" stroke="#3b82f6" stroke-width="1.5" />
  <text x="67" y="36" font-family="DejaVu Sans, Arial" font-size="10" font-weight="bold" fill="#1e3a8a" text-anchor="middle">4 Ingest</text>
  <text x="67" y="52" font-family="DejaVu Sans, Arial" font-size="8.5" fill="#2563eb" text-anchor="middle">Producers (2M)</text>

  <line x1="120" y1="42" x2="155" y2="42" stroke="#7c3aed" stroke-width="2" />
  <polygon points="155,38 163,42 155,46" fill="#7c3aed" />

  <rect x="165" y="12" width="115" height="60" rx="5" fill="#f5f3ff" stroke="#7c3aed" stroke-width="1.5" />
  <text x="222" y="32" font-family="DejaVu Sans, Arial" font-size="10" font-weight="bold" fill="#5b21b6" text-anchor="middle">Router Actor</text>
  <text x="222" y="47" font-family="DejaVu Sans, Arial" font-size="8" fill="#7c3aed" text-anchor="middle">Partition Key:</text>
  <text x="222" y="61" font-family="monospace" font-size="8.5" fill="#5b21b6" text-anchor="middle">Shard = ID mod 4</text>

  <line x1="280" y1="28" x2="320" y2="20" stroke="#7c3aed" stroke-width="1.5" />
  <polygon points="320,17 328,19 322,23" fill="#7c3aed" />
  <line x1="280" y1="56" x2="320" y2="64" stroke="#7c3aed" stroke-width="1.5" />
  <polygon points="322,61 328,65 320,67" fill="#7c3aed" />

  <rect x="330" y="8" width="185" height="68" rx="5" fill="#ffffff" stroke="#7c3aed" stroke-width="1.5" />
  <text x="422" y="24" font-family="DejaVu Sans, Arial" font-size="9" font-weight="bold" fill="#5b21b6" text-anchor="middle">4 Shard Channels &amp; Workers</text>
  <text x="422" y="39" font-family="DejaVu Sans, Arial" font-size="7.5" fill="#334155" text-anchor="middle">Shard_0 • Shard_1 • Shard_2 • Shard_3</text>
  <text x="422" y="53" font-family="DejaVu Sans, Arial" font-size="7.5" fill="#059669" text-anchor="middle">Parallel Checksum Accumulation</text>
  <text x="422" y="67" font-family="DejaVu Serif, Georgia" font-size="8" font-style="italic" fill="#0f172a" text-anchor="middle">CRC_total = CRC_0 + CRC_1 + CRC_2 + CRC_3</text>

  <line x1="515" y1="42" x2="550" y2="42" stroke="#7c3aed" stroke-width="2" />
  <polygon points="550,38 558,42 550,46" fill="#7c3aed" />

  <rect x="560" y="12" width="125" height="60" rx="5" fill="#f0fdf4" stroke="#16a34a" stroke-width="1.5" />
  <text x="622" y="32" font-family="DejaVu Sans, Arial" font-size="10" font-weight="bold" fill="#14532d" text-anchor="middle">Aggregator</text>
  <text x="622" y="47" font-family="DejaVu Sans, Arial" font-size="8.5" fill="#16a34a" text-anchor="middle">Fan-In Consolidation</text>
  <text x="622" y="61" font-family="DejaVu Sans, Arial" font-size="8" fill="#64748b" text-anchor="middle">8M Message Transfers</text>
</svg>'''

    # -------------------------------------------------------------
    # 5. SCHEME TEST 4: 2D Laplace & Barrier (UA & EN)
    # -------------------------------------------------------------
    svg_test4_ua = '''<svg width="700" height="85" viewBox="0 0 700 85" xmlns="http://www.w3.org/2000/svg">
  <rect width="700" height="85" rx="6" fill="#f8fafc" stroke="#cbd5e1" stroke-width="1.5" />
  <rect x="0" y="0" width="6" height="85" rx="3" fill="#ea580c" />

  <rect x="15" y="10" width="215" height="65" rx="5" fill="#fff7ed" stroke="#ea580c" stroke-width="1.5" />
  <text x="122" y="27" font-family="DejaVu Sans, Arial" font-size="10" font-weight="bold" fill="#9a3412" text-anchor="middle">2D Сітка 1000 × 2000 (2M)</text>
  <text x="122" y="43" font-family="DejaVu Sans, Arial" font-size="8" fill="#ea580c" text-anchor="middle">Декомпозиція: 12 смуг по 166 рядків</text>
  <line x1="25" y1="49" x2="220" y2="49" stroke="#fed7aa" stroke-width="1" />
  <text x="122" y="64" font-family="DejaVu Sans, Arial" font-size="8" fill="#64748b" text-anchor="middle">12 потоків, 100M оновлень</text>

  <line x1="230" y1="42" x2="265" y2="42" stroke="#ea580c" stroke-width="2" />
  <polygon points="265,38 273,42 265,46" fill="#ea580c" />

  <rect x="275" y="10" width="245" height="65" rx="5" fill="#ffffff" stroke="#ea580c" stroke-width="1.5" />
  <text x="397" y="26" font-family="DejaVu Sans, Arial" font-size="9.5" font-weight="bold" fill="#9a3412" text-anchor="middle">5-точковий шаблон Лапласа</text>
  <text x="397" y="44" font-family="DejaVu Serif, Georgia" font-size="9" font-style="italic" fill="#0f172a" text-anchor="middle">U[i,j](t+1) = 0.25 × (U_up + U_down + U_left + U_right)</text>
  <text x="397" y="62" font-family="DejaVu Sans, Arial" font-size="7.5" fill="#059669" text-anchor="middle">SIMD/AVX дружній лінійний доступ до пам'яті</text>

  <line x1="520" y1="42" x2="550" y2="42" stroke="#ea580c" stroke-width="2" />
  <polygon points="550,38 558,42 550,46" fill="#ea580c" />

  <rect x="560" y="10" width="125" height="65" rx="5" fill="#eff6ff" stroke="#2563eb" stroke-width="1.5" />
  <text x="622" y="27" font-family="DejaVu Sans, Arial" font-size="9.5" font-weight="bold" fill="#1e3a8a" text-anchor="middle">TBarrier (50 фаз)</text>
  <text x="622" y="43" font-family="DejaVu Sans, Arial" font-size="8" fill="#2563eb" text-anchor="middle">SignalAndWait</text>
  <line x1="570" y1="49" x2="675" y2="49" stroke="#bfdbfe" stroke-width="1" />
  <text x="622" y="64" font-family="DejaVu Sans, Arial" font-size="7.5" fill="#1e3a8a" text-anchor="middle">PostPhase: Swap(A, B)</text>
</svg>'''

    svg_test4_en = '''<svg width="700" height="85" viewBox="0 0 700 85" xmlns="http://www.w3.org/2000/svg">
  <rect width="700" height="85" rx="6" fill="#f8fafc" stroke="#cbd5e1" stroke-width="1.5" />
  <rect x="0" y="0" width="6" height="85" rx="3" fill="#ea580c" />

  <rect x="15" y="10" width="215" height="65" rx="5" fill="#fff7ed" stroke="#ea580c" stroke-width="1.5" />
  <text x="122" y="27" font-family="DejaVu Sans, Arial" font-size="10" font-weight="bold" fill="#9a3412" text-anchor="middle">2D Grid 1000 × 2000 (2M)</text>
  <text x="122" y="43" font-family="DejaVu Sans, Arial" font-size="8" fill="#ea580c" text-anchor="middle">Domain Decomposition: 12 stripes</text>
  <line x1="25" y1="49" x2="220" y2="49" stroke="#fed7aa" stroke-width="1" />
  <text x="122" y="64" font-family="DejaVu Sans, Arial" font-size="8" fill="#64748b" text-anchor="middle">12 threads, 100M cell updates</text>

  <line x1="230" y1="42" x2="265" y2="42" stroke="#ea580c" stroke-width="2" />
  <polygon points="265,38 273,42 265,46" fill="#ea580c" />

  <rect x="275" y="10" width="245" height="65" rx="5" fill="#ffffff" stroke="#ea580c" stroke-width="1.5" />
  <text x="397" y="26" font-family="DejaVu Sans, Arial" font-size="9.5" font-weight="bold" fill="#9a3412" text-anchor="middle">5-Point Discrete Laplace Stencil</text>
  <text x="397" y="44" font-family="DejaVu Serif, Georgia" font-size="9" font-style="italic" fill="#0f172a" text-anchor="middle">U[i,j](t+1) = 0.25 × (U_up + U_down + U_left + U_right)</text>
  <text x="397" y="62" font-family="DejaVu Sans, Arial" font-size="7.5" fill="#059669" text-anchor="middle">SIMD/AVX linear memory cache locality</text>

  <line x1="520" y1="42" x2="550" y2="42" stroke="#ea580c" stroke-width="2" />
  <polygon points="550,38 558,42 550,46" fill="#ea580c" />

  <rect x="560" y="10" width="125" height="65" rx="5" fill="#eff6ff" stroke="#2563eb" stroke-width="1.5" />
  <text x="622" y="27" font-family="DejaVu Sans, Arial" font-size="9.5" font-weight="bold" fill="#1e3a8a" text-anchor="middle">TBarrier (50 Phases)</text>
  <text x="622" y="43" font-family="DejaVu Sans, Arial" font-size="8" fill="#2563eb" text-anchor="middle">SignalAndWait</text>
  <line x1="570" y1="49" x2="675" y2="49" stroke="#bfdbfe" stroke-width="1" />
  <text x="622" y="64" font-family="DejaVu Sans, Arial" font-size="7.5" fill="#1e3a8a" text-anchor="middle">PostPhase: Swap(A, B)</text>
</svg>'''

    # -------------------------------------------------------------
    # 6. SCHEME TEST 5: ACID Banking Ledger (UA & EN)
    # -------------------------------------------------------------
    svg_test5_ua = '''<svg width="700" height="85" viewBox="0 0 700 85" xmlns="http://www.w3.org/2000/svg">
  <rect width="700" height="85" rx="6" fill="#f8fafc" stroke="#cbd5e1" stroke-width="1.5" />
  <rect x="0" y="0" width="6" height="85" rx="3" fill="#059669" />

  <rect x="15" y="10" width="180" height="65" rx="5" fill="#eff6ff" stroke="#2563eb" stroke-width="1.5" />
  <text x="105" y="26" font-family="DejaVu Sans, Arial" font-size="10" font-weight="bold" fill="#1e3a8a" text-anchor="middle">2 000 000 Транзакцій</text>
  <text x="105" y="40" font-family="DejaVu Sans, Arial" font-size="8" fill="#0284c7" text-anchor="middle">70% Баланс (Shared Read)</text>
  <text x="105" y="53" font-family="DejaVu Sans, Arial" font-size="8" fill="#16a34a" text-anchor="middle">20% Поповнення (Lock-free CAS)</text>
  <text x="105" y="66" font-family="DejaVu Sans, Arial" font-size="8" fill="#dc2626" text-anchor="middle">10% Перекази (Впорядковані замки)</text>

  <line x1="195" y1="42" x2="235" y2="42" stroke="#059669" stroke-width="2" />
  <polygon points="235,38 243,42 235,46" fill="#059669" />

  <rect x="245" y="10" width="250" height="65" rx="5" fill="#ffffff" stroke="#059669" stroke-width="1.5" />
  <text x="370" y="26" font-family="DejaVu Sans, Arial" font-size="9.5" font-weight="bold" fill="#14532d" text-anchor="middle">Захист від Deadlock та CAS</text>
  <text x="370" y="42" font-family="DejaVu Sans, Arial" font-size="8" fill="#16a34a" text-anchor="middle">CAS: InterlockedCompareExchange64</text>
  <line x1="260" y1="48" x2="480" y2="48" stroke="#bbf7d0" stroke-width="1" />
  <text x="370" y="64" font-family="DejaVu Serif, Georgia" font-size="8" fill="#0f172a" text-anchor="middle">Ієрархія: Lock(min(A, B)) → Lock(max(A, B))</text>

  <line x1="495" y1="42" x2="530" y2="42" stroke="#059669" stroke-width="2" />
  <polygon points="530,38 538,42 530,46" fill="#059669" />

  <rect x="540" y="10" width="145" height="65" rx="5" fill="#f0fdf4" stroke="#16a34a" stroke-width="1.5" />
  <text x="612" y="26" font-family="DejaVu Sans, Arial" font-size="9.5" font-weight="bold" fill="#14532d" text-anchor="middle">Інваріант ACID</text>
  <text x="612" y="43" font-family="DejaVu Serif, Georgia" font-size="8.5" font-style="italic" fill="#0f172a" text-anchor="middle">∑ Balance = $5,002,000</text>
  <line x1="550" y1="49" x2="675" y2="49" stroke="#bbf7d0" stroke-width="1" />
  <text x="612" y="64" font-family="DejaVu Sans, Arial" font-size="8" font-weight="bold" fill="#059669" text-anchor="middle">Δ = 0.00 (Збережено)</text>
</svg>'''

    svg_test5_en = '''<svg width="700" height="85" viewBox="0 0 700 85" xmlns="http://www.w3.org/2000/svg">
  <rect width="700" height="85" rx="6" fill="#f8fafc" stroke="#cbd5e1" stroke-width="1.5" />
  <rect x="0" y="0" width="6" height="85" rx="3" fill="#059669" />

  <rect x="15" y="10" width="180" height="65" rx="5" fill="#eff6ff" stroke="#2563eb" stroke-width="1.5" />
  <text x="105" y="26" font-family="DejaVu Sans, Arial" font-size="10" font-weight="bold" fill="#1e3a8a" text-anchor="middle">2,000,000 Transactions</text>
  <text x="105" y="40" font-family="DejaVu Sans, Arial" font-size="8" fill="#0284c7" text-anchor="middle">70% Inquiries (Shared Read)</text>
  <text x="105" y="53" font-family="DejaVu Sans, Arial" font-size="8" fill="#16a34a" text-anchor="middle">20% Deposits (Lock-free CAS)</text>
  <text x="105" y="66" font-family="DejaVu Sans, Arial" font-size="8" fill="#dc2626" text-anchor="middle">10% Transfers (Ordered Locks)</text>

  <line x1="195" y1="42" x2="235" y2="42" stroke="#059669" stroke-width="2" />
  <polygon points="235,38 243,42 235,46" fill="#059669" />

  <rect x="245" y="10" width="250" height="65" rx="5" fill="#ffffff" stroke="#059669" stroke-width="1.5" />
  <text x="370" y="26" font-family="DejaVu Sans, Arial" font-size="9.5" font-weight="bold" fill="#14532d" text-anchor="middle">Deadlock Prevention &amp; CAS</text>
  <text x="370" y="42" font-family="DejaVu Sans, Arial" font-size="8" fill="#16a34a" text-anchor="middle">CAS: InterlockedCompareExchange64</text>
  <line x1="260" y1="48" x2="480" y2="48" stroke="#bbf7d0" stroke-width="1" />
  <text x="370" y="64" font-family="DejaVu Serif, Georgia" font-size="8" fill="#0f172a" text-anchor="middle">Ordered Locks: Lock(min(A, B)) → Lock(max(A, B))</text>

  <line x1="495" y1="42" x2="530" y2="42" stroke="#059669" stroke-width="2" />
  <polygon points="530,38 538,42 530,46" fill="#059669" />

  <rect x="540" y="10" width="145" height="65" rx="5" fill="#f0fdf4" stroke="#16a34a" stroke-width="1.5" />
  <text x="612" y="26" font-family="DejaVu Sans, Arial" font-size="9.5" font-weight="bold" fill="#14532d" text-anchor="middle">ACID Invariant</text>
  <text x="612" y="43" font-family="DejaVu Serif, Georgia" font-size="8.5" font-style="italic" fill="#0f172a" text-anchor="middle">∑ Balance = $5,002,000</text>
  <line x1="550" y1="49" x2="675" y2="49" stroke="#bbf7d0" stroke-width="1" />
  <text x="612" y="64" font-family="DejaVu Sans, Arial" font-size="8" font-weight="bold" fill="#059669" text-anchor="middle">Δ = 0.00 (Conserved)</text>
</svg>'''

    all_diagrams = [
        ('formula_metrics_ua', svg_metrics_ua),
        ('formula_metrics_en', svg_metrics_en),
        ('scheme_test1_ua', svg_test1_ua),
        ('scheme_test1_en', svg_test1_en),
        ('scheme_test2_ua', svg_test2_ua),
        ('scheme_test2_en', svg_test2_en),
        ('scheme_test3_ua', svg_test3_ua),
        ('scheme_test3_en', svg_test3_en),
        ('scheme_test4_ua', svg_test4_ua),
        ('scheme_test4_en', svg_test4_en),
        ('scheme_test5_ua', svg_test5_ua),
        ('scheme_test5_en', svg_test5_en),
    ]

    for name, content in all_diagrams:
        svg_file = os.path.join(img_dir, f'{name}.svg')
        png_file = os.path.join(img_dir, f'{name}.png')
        with open(svg_file, 'w', encoding='utf-8') as f:
            f.write(content)
        cmd = f'convert -density 96 {svg_file} {png_file}'
        subprocess.run(cmd, shell=True, check=True)
        print(f'Successfully built {name}.png')

if __name__ == '__main__':
    generate_svgs()
