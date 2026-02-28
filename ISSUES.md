# RuboCop 標準ルール ギャップ Issue 一覧

対象: RuboCop `Layout` 部門（標準で有効な cop を優先）

実装済み:
- [x] `Layout/SpaceAroundOperators` (`operator_spacing.zig`)
- [x] `Layout/DotPosition` 相当（メソッドチェーンの整列として一部対応, `align_method_chain.zig`)
- [x] `Layout/SpaceInsideBlockBraces` (`block_brace_spacing.zig`)
- [x] `Layout/LeadingEmptyLines` (`leading_empty_lines.zig`)
- [x] `Layout/TrailingEmptyLines` (`trailing_empty_lines.zig`)
- [x] `Layout/SpaceBeforeComma` (`space_before_comma.zig`)
- [x] `Layout/SpaceBeforeComment` (`space_before_comment.zig`)

未実装 Issue:
1. `Issue: Layout/TrailingWhitespace`
   - 末尾空白（space/tab）を削除する
   - 低リスクで自動修正しやすいため最優先
2. `Issue: Layout/EmptyLinesAroundModifier` ✅
   - https://github.com/atolix/rx/issues/10
   - 修飾子付き `if/unless` 前後の空行ルールを統一する
   - 既存 `guard_blank_line` との差分を埋める
3. `Issue: Layout/LineLength`
   - https://github.com/atolix/rx/issues/11
   - 最大行長超過の検出・自動折り返し（段階的導入）
4. `Issue: Layout/IndentationWidth` ✅
   - https://github.com/atolix/rx/issues/12
   - インデント幅（標準2スペース）の強制
5. `Issue: Layout/SpaceInsideParens` ✅
   - https://github.com/atolix/rx/issues/13
   - 丸括弧内スペースの統一
6. `Issue: Layout/SpaceAfterComma` ✅
   - https://github.com/atolix/rx/issues/14
   - カンマ後スペースの統一
7. `Issue: Layout/HashAlignment`
   - https://github.com/atolix/rx/issues/15
   - 複数行ハッシュのキー・セパレータ整列

参考:
- https://docs.rubocop.org/rubocop/cops_layout.html
- https://docs.rubocop.org/rubocop/configuration.html
