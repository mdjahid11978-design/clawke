from __future__ import annotations

from pathlib import Path

from skill_adapter import HermesSkillAdapter


def test_hermes_skill_adapter_manages_gateway_host_clawke_skills(tmp_path: Path):
    adapter = HermesSkillAdapter(clawke_home=tmp_path)

    created = adapter.create_skill({
        "name": "apple-notes",
        "category": "apple",
        "description": "Manage Apple Notes",
        "trigger": "Use for notes",
        "body": "# Apple Notes\n",
    })

    assert created["id"] == "apple/apple-notes"
    assert created["source"] == "managed"
    assert created["enabled"] is True
    assert (tmp_path / "skills" / "apple-notes" / "SKILL.md").exists()

    listed = adapter.list_skills()
    assert [skill["id"] for skill in listed] == ["apple/apple-notes"]

    disabled = adapter.set_enabled("apple/apple-notes", False)
    assert disabled["enabled"] is False
    assert not (tmp_path / "skills" / "apple-notes" / "SKILL.md").exists()
    assert (tmp_path / "disabled-skills" / "apple-notes" / "SKILL.md").exists()

    restored = adapter.set_enabled("apple/apple-notes", True)
    assert restored["enabled"] is True
    assert (tmp_path / "skills" / "apple-notes" / "SKILL.md").exists()
