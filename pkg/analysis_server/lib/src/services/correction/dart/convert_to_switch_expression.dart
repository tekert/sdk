// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/assist.dart';
import 'package:analysis_server/src/services/correction/dart/abstract_producer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer/src/dart/element/type_system.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_dart.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

class ConvertToSwitchExpression extends CorrectionProducer {
  /// Local variable reference used in assignment switch expression generation.
  LocalVariableElement? writeElement;

  /// Function reference used in argument switch expression generation.
  FunctionElement? functionElement;

  @override
  AssistKind get assistKind => DartAssistKind.CONVERT_TO_SWITCH_EXPRESSION;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    var node = this.node;
    if (node is! SwitchStatement) return;

    var expression = node.expression;
    if (!isEffectivelyExhaustive(expression.staticType, node)) return;

    if (isReturnSwitch(node)) {
      await convertReturnSwitchExpression(builder, node);
    } else if (isAssignmentSwitch(node)) {
      await convertAssignmentSwitchExpression(builder, node);
    } else if (isArgumentSwitch(node)) {
      await convertArgumentSwitchExpression(builder, node);
    }
  }

  Future<void> convertArgumentSwitchExpression(
      ChangeBuilder builder, SwitchStatement node) async {
    void convertArgumentStatements(DartFileEditBuilder builder,
        NodeList<Statement> statements, SourceRange colonRange,
        {String endToken = ''}) {
      for (var statement in statements) {
        var hasComment = statement.beginToken.precedingComments != null;

        if (statement is ExpressionStatement) {
          var invocation = statement.expression;
          if (invocation is MethodInvocation) {
            var deletion = !hasComment
                ? range.startOffsetEndOffset(
                    range.offsetBy(colonRange, 1).offset,
                    invocation.argumentList.leftParenthesis.end)
                : range.startOffsetEndOffset(invocation.offset,
                    invocation.argumentList.leftParenthesis.end);
            builder.addDeletion(deletion);
            builder.addDeletion(
                range.entity(invocation.argumentList.rightParenthesis));
          }
        }

        if (!hasComment && statement.isThrowExpressionStatement) {
          var deletionRange = range.startOffsetEndOffset(
              range.offsetBy(colonRange, 1).offset, statement.offset - 1);
          builder.addDeletion(deletionRange);
        }

        if (statement is BreakStatement) {
          var deletion = getBreakRange(statement);
          builder.addDeletion(deletion);
        } else {
          builder.addSimpleReplacement(
              range.entity(statement.endToken), endToken);
        }
      }
    }

    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleInsertion(node.offset, '${functionElement!.name}(');

      var memberCount = node.members.length;
      for (var i = 0; i < memberCount; ++i) {
        var member = node.members[i];
        if (member is SwitchDefault) {
          convertSwitchDefault(builder, member);
          convertArgumentStatements(
              builder, member.statements, range.entity(member.colon));
          continue;
        }
        // Sure to be a SwitchPatternCase
        var patternCase = member as SwitchPatternCase;
        builder.addDeletion(
            range.startStart(patternCase.keyword, patternCase.guardedPattern));
        var colonRange = range.entity(patternCase.colon);
        builder.addSimpleReplacement(colonRange, ' => ');

        var endToken = i < memberCount - 1 ? ',' : '';
        convertArgumentStatements(builder, patternCase.statements, colonRange,
            endToken: endToken);
      }

      builder.addSimpleInsertion(node.end, ');');
    });
  }

  Future<void> convertAssignmentSwitchExpression(
      ChangeBuilder builder, SwitchStatement node) async {
    void convertAssignmentStatements(DartFileEditBuilder builder,
        NodeList<Statement> statements, SourceRange colonRange,
        {String endToken = ''}) {
      for (var statement in statements) {
        if (statement is ExpressionStatement) {
          var expression = statement.expression;
          if (expression is AssignmentExpression) {
            var hasComment = statement.beginToken.precedingComments != null;
            var deletion = !hasComment
                ? range.startOffsetEndOffset(
                    range.offsetBy(colonRange, 1).offset,
                    expression.operator.end)
                : range.startOffsetEndOffset(expression.beginToken.offset,
                    expression.rightHandSide.offset);
            builder.addDeletion(deletion);
          } else if (expression is ThrowExpression) {
            var deletionRange = range.startOffsetEndOffset(
                range.offsetBy(colonRange, 1).offset, statement.offset - 1);
            builder.addDeletion(deletionRange);
          }
        }

        if (statement is BreakStatement) {
          var deletion = getBreakRange(statement);
          builder.addDeletion(deletion);
        } else {
          builder.addSimpleReplacement(
              range.entity(statement.endToken), endToken);
        }
      }
    }

    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleInsertion(node.offset, '${writeElement!.name} = ');

      var memberCount = node.members.length;
      for (var i = 0; i < memberCount; ++i) {
        // todo(pq): extract shared replacement logic
        var member = node.members[i];
        if (member is SwitchDefault) {
          convertSwitchDefault(builder, member);
          convertAssignmentStatements(
              builder, member.statements, range.entity(member.colon));
          continue;
        }

        // Sure to be a SwitchPatternCase
        var patternCase = member as SwitchPatternCase;
        builder.addDeletion(
            range.startStart(patternCase.keyword, patternCase.guardedPattern));
        var colonRange = range.entity(patternCase.colon);
        builder.addSimpleReplacement(colonRange, ' =>');

        var endToken = i < memberCount - 1 ? ',' : '';
        convertAssignmentStatements(builder, patternCase.statements, colonRange,
            endToken: endToken);
      }

      builder.addSimpleInsertion(node.end, ';');
    });
  }

  Future<void> convertReturnSwitchExpression(
      ChangeBuilder builder, SwitchStatement node) async {
    void convertReturnStatement(DartFileEditBuilder builder,
        Statement statement, SourceRange colonRange,
        {String endToken = ''}) {
      var hasComment = statement.beginToken.precedingComments != null;

      if (statement is ReturnStatement) {
        // Return expression is sure to be non-null
        var deletion = !hasComment
            ? range.startOffsetEndOffset(range.offsetBy(colonRange, 1).offset,
                statement.expression!.offset - 1)
            : range.startStart(statement.returnKeyword, statement.expression!);
        builder.addDeletion(deletion);
      }

      if (!hasComment && statement.isThrowExpressionStatement) {
        var deletionRange = range.startOffsetEndOffset(
            range.offsetBy(colonRange, 1).offset, statement.offset - 1);
        builder.addDeletion(deletionRange);
      }

      builder.addSimpleReplacement(range.entity(statement.endToken), endToken);
    }

    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleInsertion(node.offset, 'return ');
      builder.addSimpleInsertion(node.end, ';');

      var memberCount = node.members.length;
      for (var i = 0; i < memberCount; ++i) {
        // todo(pq): extract shared replacement logic
        var member = node.members[i];
        if (member is SwitchDefault) {
          convertSwitchDefault(builder, member);
          convertReturnStatement(
              builder, member.statements.first, range.entity(member.colon));
          continue;
        }
        // Sure to be a SwitchPatternCase
        var patternCase = member as SwitchPatternCase;
        builder.addDeletion(
            range.startStart(patternCase.keyword, patternCase.guardedPattern));
        var colonRange = range.entity(patternCase.colon);
        builder.addSimpleReplacement(colonRange, ' =>');

        var statement = patternCase.statements.first;
        var endToken = i < memberCount - 1 ? ',' : '';
        convertReturnStatement(builder, statement, colonRange,
            endToken: endToken);
      }
    });
  }

  void convertSwitchDefault(DartFileEditBuilder builder, SwitchDefault member) {
    var defaultClauseRange = range.startEnd(member.keyword, member.colon);
    builder.addSimpleReplacement(defaultClauseRange, '_ =>');
  }

  SourceRange getBreakRange(BreakStatement statement) {
    var previous = (statement.beginToken.precedingComments ??
        statement.beginToken.previous)!;
    var deletion =
        range.startOffsetEndOffset(previous.end, statement.endToken.end);
    return deletion;
  }

  // todo(pq): refactor the `is` checks to a single `getSwitchKind`
  // that only looks at members once
  // see: https://dart-review.googlesource.com/c/sdk/+/287904
  bool isArgumentSwitch(SwitchStatement node) {
    for (var member in node.members) {
      if (member is! SwitchPatternCase && member is! SwitchDefault) {
        return false;
      }
      if (member.labels.isNotEmpty) return false;
      var statements = member.statements;
      if (statements.length == 1) {
        if (statements.first.isThrowExpressionStatement) continue;
      } else if (statements.length == 2) {
        if (statements[1] is! BreakStatement) return false;
      } else {
        return false;
      }

      var s = statements.first;
      if (s is! ExpressionStatement) return false;
      var expression = s.expression;
      if (expression is! MethodInvocation) return false;
      var element = expression.methodName.staticElement;
      if (element is! FunctionElement) return false;
      if (functionElement == null) {
        functionElement = element;
      } else {
        if (functionElement != element) return false;
      }
    }

    return functionElement != null;
  }

  bool isAssignmentSwitch(SwitchStatement node) {
    for (var member in node.members) {
      if (member is! SwitchPatternCase && member is! SwitchDefault) {
        return false;
      }
      if (member.labels.isNotEmpty) return false;
      var statements = member.statements;
      if (statements.length == 1) {
        if (statements.first.isThrowExpressionStatement) continue;
      } else if (statements.length == 2) {
        if (statements[1] is! BreakStatement) return false;
      } else {
        return false;
      }

      var s = statements.first;
      if (s is! ExpressionStatement) return false;
      var expression = s.expression;
      if (expression is! AssignmentExpression) return false;
      var leftHandSide = expression.leftHandSide;
      if (leftHandSide is! SimpleIdentifier) return false;
      if (writeElement == null) {
        var element = leftHandSide.staticElement;
        if (element is! LocalVariableElement) return false;
        writeElement = element;
      } else {
        if (writeElement != leftHandSide.staticElement) return false;
      }
    }

    return writeElement != null;
  }

  bool isEffectivelyExhaustive(DartType? type, SwitchStatement node) {
    if (type == null) return false;
    if ((typeSystem as TypeSystemImpl).isAlwaysExhaustive(type)) return true;
    var last = node.members.lastOrNull;
    if (last is SwitchPatternCase) {
      var pattern = last.guardedPattern.pattern;
      return pattern is WildcardPattern;
    }
    return last is SwitchDefault;
  }

  bool isReturnSwitch(SwitchStatement node) {
    for (var member in node.members) {
      if (member is! SwitchPatternCase && member is! SwitchDefault) {
        return false;
      }
      if (member.labels.isNotEmpty) return false;
      var statements = member.statements;
      if (statements.length != 1) return false;
      var s = statements.first;
      if (s is ReturnStatement && s.expression != null) continue;
      if (s is! ExpressionStatement || s.expression is! ThrowExpression) {
        return false;
      }
    }
    return true;
  }
}

extension on Statement {
  bool get isThrowExpressionStatement {
    var self = this;
    if (self is! ExpressionStatement) return false;
    return self.expression is ThrowExpression;
  }
}
