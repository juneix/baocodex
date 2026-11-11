// YCode — GPL-3.0-only.
import 'package:flutter/material.dart';

import '../chat_models.dart';
import 'edit_step.dart';
import 'step_header.dart';

/// The line a run of edits folds into: "编辑 5 次 +40 −3", one per edit it
/// opens to (a file edited twice is two), the counts all of theirs.
class EditsFoldLine extends StatelessWidget {
  const EditsFoldLine({
    super.key,
    required this.edits,
    required this.expanded,
    required this.onToggle,
    required this.zh,
  });

  final List<CodeDiffItem> edits;
  final bool expanded;
  final VoidCallback onToggle;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final added = edits.fold(0, (sum, edit) => sum + edit.added);
    final removed = edits.fold(0, (sum, edit) => sum + edit.removed);
    final count = edits.length;
    return StepHeader(
      verb: zh ? '编辑' : 'Edited',
      object: zh ? '$count 次' : (count == 1 ? 'once' : '$count times'),
      expanded: expanded,
      onToggle: onToggle,
      trailing: Text.rich(
        TextSpan(
          children: [
            if (added > 0)
              TextSpan(
                text: '+$added',
                style: TextStyle(color: EditStep.addedForeground(dark)),
              ),
            if (added > 0 && removed > 0) const TextSpan(text: ' '),
            if (removed > 0)
              TextSpan(
                text: '-$removed',
                style: TextStyle(color: EditStep.removedForeground(dark)),
              ),
          ],
        ),
        style: EditStep.countStyle,
      ),
    );
  }
}
