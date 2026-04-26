import 'package:client/models/managed_skill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('displayPath does not prefix root when path is already absolute', () {
    const skill = ManagedSkill(
      id: 'openclaw-workspace/gstack-openclaw-investigate',
      name: 'gstack-openclaw-investigate',
      description: 'Debugging',
      category: 'openclaw-workspace',
      enabled: true,
      source: 'external',
      sourceLabel: 'OpenClaw openclaw-workspace',
      writable: true,
      deletable: true,
      path:
          '/Users/samy/.openclaw/workspace/skills/gstack-openclaw-investigate/SKILL.md',
      root: '/Users/samy/.openclaw/workspace/skills/gstack-openclaw-investigate',
      updatedAt: 0,
      hasConflict: false,
    );

    expect(
      skill.displayPath,
      '/Users/samy/.openclaw/workspace/skills/gstack-openclaw-investigate/SKILL.md',
    );
  });
}
