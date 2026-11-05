#!/usr/bin/env python3
"""Source unique du programme d'entraînement.

Génère :
  - App/Resources/program.json    (seed local SwiftData, offline-first)
  - supabase/seed.sql             (seed des templates globaux côté Supabase)

Les UUID sont déterministes (uuid5) : le template local et le template cloud
ont donc exactement le même identifiant, ce qui évite tout doublon à la sync.

Usage : python3 scripts/generate_program.py
"""
import json
import pathlib
import uuid

ROOT = pathlib.Path(__file__).resolve().parent.parent
NS = uuid.UUID("6f1c2a52-3c1e-4c7a-9a43-1f0d2b7e9a10")

M, D, A, B = "machine", "dumbbell", "assisted", "bodyweight"
FIN = 0


def ex(key, name, load_type, sets):
    return {"key": key, "name": name, "loadType": load_type, "sets": sets}


def w(rest):  # échauffement
    return {"kind": "warmup", "rest": rest}


def s(rest):  # série effective
    return {"kind": "working", "rest": rest}


PROGRAM = [
    ("Séance 1", "Pectoraux & Triceps", "figure.strengthtraining.traditional", [
        ex("pec_deck", "Pec Deck", M, [w(90), s(90), s(180)]),
        ex("chest_press_plate_incline", "Chest press à disque - Incliné/convergente", M, [w(120), s(120), s(180)]),
        ex("overhead_triceps_cable", "Overhead triceps extension poulie", M, [s(90), s(90), s(180)]),
        ex("single_arm_triceps_cable", "Extension triceps unilatérale poulie", M, [s(90), s(90), s(FIN)]),
    ]),
    ("Séance 2", "Dos & Biceps", "figure.climbing", [
        ex("assisted_pull_up", "Tractions délestées", A, [s(120), s(120), s(180)]),
        ex("seated_cable_row_v", "Rowing horizontal poulie - poignée V", M, [s(120), s(120), s(180)]),
        ex("incline_bench_curl", "Curl banc incliné - assis, 2 bras", D, [s(90), s(90), s(180)]),
        ex("bench_90_single_curl", "Curl banc à 90° - debout, unilatéral", D, [s(90), s(90), s(FIN)]),
    ]),
    ("Séance 3", "Épaules & Bras", "figure.arms.open", [
        ex("machine_shoulder_press", "Développé militaire machine", M, [s(120), s(120), s(180)]),
        ex("lateral_raise", "Élévations latérales", D, [s(90), s(90), s(180)]),
        ex("reverse_pec_deck", "Reverse Pec Deck", M, [s(90), s(90), s(180)]),
        ex("hammer_curl", "Curl marteau", D, [s(90), s(90), s(180)]),
        ex("single_arm_triceps_cable", "Extension triceps unilatérale poulie", M, [s(90), s(90), s(FIN)]),
    ]),
    ("Séance 4", "Pectoraux, Dos & Avant-bras", "figure.mixed.cardio", [
        ex("incline_db_chest_press", "Chest press incliné haltères", D, [w(120), s(120), s(180)]),
        ex("seated_cable_pull_v", "Tirage horizontal poulie - poignée V", M, [s(120), s(120), s(180)]),
        ex("pec_fly", "Pec Fly", M, [s(90), s(90), s(180)]),
        ex("converging_row_machine", "Rowing machine convergente", M, [s(120), s(120), s(180)]),
        ex("strict_wrist_curl", "Curl avant-bras strict", D, [s(60), s(60), s(180)]),
        ex("reverse_curl", "Reverse curl", M, [s(60), s(60), s(FIN)]),
    ]),
]


def build():
    templates = []
    for order, (title, subtitle, symbol, exercises) in enumerate(PROGRAM, start=1):
        tid = str(uuid.uuid5(NS, f"template-{order}"))
        templates.append({
            "id": tid,
            "order": order,
            "title": title,
            "subtitle": subtitle,
            "symbol": symbol,
            "exercises": [
                {
                    **e,
                    "sets": [
                        {"index": i, "kind": st["kind"], "restSeconds": st["rest"], "targetReps": None}
                        for i, st in enumerate(e["sets"])
                    ],
                }
                for e in exercises
            ],
        })
    return templates


def sql_literal(text: str) -> str:
    return "'" + text.replace("'", "''") + "'"


def main():
    templates = build()
    (ROOT / "App/Resources/program.json").write_text(
        json.dumps(templates, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    lines = [
        "-- ⚠️ Fichier généré par scripts/generate_program.py — ne pas éditer à la main.",
        "-- Templates globaux (user_id NULL) visibles par tous les utilisateurs authentifiés.",
        "insert into public.workout_templates (id, user_id, sort_order, title, subtitle, symbol, exercises)",
        "values",
    ]
    rows = []
    for t in templates:
        rows.append(
            f"  ({sql_literal(t['id'])}, null, {t['order']}, {sql_literal(t['title'])}, "
            f"{sql_literal(t['subtitle'])}, {sql_literal(t['symbol'])}, "
            f"{sql_literal(json.dumps(t['exercises'], ensure_ascii=False))}::jsonb)"
        )
    lines.append(",\n".join(rows))
    lines.append("on conflict (id) do update set")
    lines.append("  sort_order = excluded.sort_order, title = excluded.title, subtitle = excluded.subtitle,")
    lines.append("  symbol = excluded.symbol, exercises = excluded.exercises, updated_at = now();")
    seed = "\n".join(lines) + "\n"
    (ROOT / "supabase/seed.sql").write_text(seed, encoding="utf-8")
    init = (ROOT / "supabase/migrations/20261105000000_init.sql").read_text(encoding="utf-8")
    (ROOT / "supabase/setup_all.sql").write_text(
        "-- RepForge : installation complète en un seul copier-coller (SQL Editor Supabase).\n"
        "-- = migrations/20261105000000_init.sql + seed.sql\n\n" + init + "\n" + seed,
        encoding="utf-8",
    )
    print(f"✅ {len(templates)} séances générées")


if __name__ == "__main__":
    main()
