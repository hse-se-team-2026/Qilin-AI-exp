#!/usr/bin/env python3
"""critic-E5 probe of acceptance/E5/doc_check.py (S6 mechanics): writes a minimal document that passes it on a
results tree (fake, critic/E5/fake_results.py), then adds one false sentence at a time to section 2 or 4 and
runs the committed doc_check.py unchanged. A false sentence that still gives exit 0 is a hole of the mechanics
(the verifier's judgment is then the only defence, RS6).
Usage: python3 critic/E5/doc_probe.py <e5-results-dir> <work-dir>"""
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "acceptance", "E5"))
import e5tables  # noqa: E402


def cell(table, bench, col, binding=None):
    lines = table.split("\n")
    hdr = [c.strip() for c in lines[1].strip("|").split("|")]
    for row in lines[3:]:
        c = [x.strip() for x in row.strip("|").split("|")]
        if c[0] == bench and (binding is None or c[1] == binding):
            return c[hdr.index(col)]
    raise KeyError((bench, col, binding))


def base_doc(T):
    s = {}
    s[1] = ("Прогон — отдельная JVM, повтор 0 — прогрев, затем 10 повторов; в таблицах медиана и доверительный "
            "интервал медианы по порядковым статистикам (Blackburn2025Rethinking). Основная мера памяти — минимальная куча, "
            "RSS — вторичная. Бенчмарки — срезы программ; выводы о программах делаются по покрытым срезам. "
            "Анализ — Qilin (He2022Qilin), Spark (Lhotak2003Scaling).\n\n" + T["T1"] + "\n\n" + T["T2"])
    s[2] = ("В привязках ANALYSIS и CALL_GRAPH прогон -pta=ucfs решает Spark и UCFS в одной JVM; pts(this) в ANALYSIS "
            "подаёт Spark. Прогоны antlr, bloat и checkstyle в привязке CALL_GRAPH пропущены (skipped).\n\n" + T["T3"])
    s[3] = "Фазы parse, rsm, export и import показаны в таблице.\n\n" + T["T4"]
    s[4] = "Наша минимальная куча и RSS при куче 16g показаны в таблице.\n\n" + T["T6"]
    s[5] = "Разброс — IQR и CV; ответ сравнивается с E4.\n\n" + T["T5"] + "\n\n" + T["T7"]
    s[6] = "Проба — одно наблюдение (probe-cg, probe-jdk).\n\n" + T["T8"]
    s[7] = "Срезы вместо программ: выводы — по покрытым срезам (интерпретация)."
    s[8] = "Команды: `bash scripts/ucfs/e5-vm-setup.sh`, `bash scripts/ucfs/e5-full.sh`, `python3 acceptance/E5/e5tables.py`."
    heads = ["Методика и конфигурация", "Время: UCFS против Spark", "Время UCFS по фазам", "Память",
             "Разброс времени и ответа", "Пробы за пределами бюджета", "Ограничения и угрозы валидности", "Воспроизведение"]
    return s, "# E5\n\n" + "\n\n".join("## %d. %s\n\n%s" % (i, heads[i - 1], s[i]) for i in range(1, 9)) + "\n"


def run(doc, res, path):
    open(path, "w", encoding="utf-8").write(doc)
    p = subprocess.run(["python3", os.path.join(ROOT, "acceptance", "E5", "doc_check.py"), path, res],
                       capture_output=True, text=True)
    return p.returncode, [l for l in p.stdout.splitlines() if l.startswith("FAIL")]


def main():
    res, work = sys.argv[1], sys.argv[2]
    os.makedirs(work, exist_ok=True)
    T = {k: v for k, v in e5tables.render(res).items()}
    s, doc = base_doc(T)
    rc, fails = run(doc, res, os.path.join(work, "base.md"))
    print("base document: doc_check exit %d %s" % (rc, fails[:3]))
    if rc:
        return 1
    t3, t6 = T["T3"], T["T6"]
    a_ucfs = cell(t3, "antlr", "UCFS ms", "ANALYSIS").split()[0]
    a_spark = cell(t3, "antlr", "Spark ms", "ANALYSIS").split()[0]
    a_ratio = cell(t3, "antlr", "UCFS/Spark", "ANALYSIS").split()[0]
    f_ratio = cell(t3, "fop", "UCFS/Spark", "ANALYSIS").split()[0]
    mh_ins = cell(t6, "antlr", "min heap MB", None)
    print("facts of the fake tables: antlr ANALYSIS UCFS %s ms, Spark %s ms, UCFS/Spark %s; fop UCFS/Spark %s; "
          "antlr insens min heap %s MB" % (a_ucfs, a_spark, a_ratio, f_ratio, mh_ins))
    probes = [
        ("whitelisted factor: 'в 100 раз' (truth: %s)" % a_ratio, 2,
         "На antlr UCFS медленнее Spark в 100 раз: UCFS %s мс." % a_ucfs),
        ("wrong small factor bound to antlr: 'в 7 раз' (truth: %s)" % a_ratio, 2,
         "На antlr UCFS медленнее Spark в 7 раз."),
        ("wrong direction with a true number: 'UCFS быстрее Spark' on antlr", 2,
         "На antlr UCFS быстрее Spark: Spark %s мс." % a_spark),
        ("'на порядок' with any true number", 2,
         "На antlr UCFS на порядок быстрее Spark (%s мс)." % a_spark),
        ("number of another run of the same bench (insens min heap given as ucfs-ANALYSIS)", 4,
         "На antlr минимальная куча прогона ucfs-ANALYSIS — %s MB." % mh_ins),
        ("escape hatch: 'проверено:' with a script that does not exist", 2,
         "На fop UCFS быстрее Spark в 999 раз, а на antlr медленнее в 999 раз "
         "(проверено: `bash scripts/ucfs/no-such-script.sh`)."),
        ("general claim from the tables of one fake benchmark (fop ratio < 1) without a list", 2,
         "UCFS решает быстрее Spark: отношение UCFS/Spark %s (интерпретация)." % f_ratio),
        ("control: number of luindex bound to antlr", 2, "На antlr UCFS — %s мс." % cell(t3, "luindex", "UCFS ms", "ANALYSIS").split()[0]),
        ("control: comparison over two benchmarks without a source", 2,
         "На antlr UCFS медленнее, чем на fop: %s мс." % a_ucfs),
    ]
    out = []
    for name, sec, sent in probes:
        marker = "## %d. " % sec
        i = doc.index(marker)
        j = doc.index("\n\n", i) + 2
        k = doc.index("\n\n", j)
        mut = doc[:k] + " " + sent + doc[k:]
        rc, fails = run(mut, res, os.path.join(work, "mut.md"))
        out.append("  %-90s -> %s" % (name, "PASSES doc_check (exit 0)" if rc == 0 else "caught: %s" % fails[0][6:120]))
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
