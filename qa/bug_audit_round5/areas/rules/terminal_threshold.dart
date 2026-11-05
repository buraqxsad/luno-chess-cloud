import 'dart:convert';
import 'dart:io';
import '/workspace/luno-chess/luno_chess/lib/battle_v1/authoritative.dart';
import '/workspace/luno-chess/luno_chess/lib/battle_v1/core.dart';
import '/workspace/luno-chess/luno_chess/lib/battle_v1/model.dart';
import '/workspace/luno-chess/luno_chess/lib/engine/board.dart';
import '/workspace/luno-chess/luno_chess/lib/engine/piece.dart';

int assertions=0,prefixTransitions=0,finalMoves=0,quietThreshold=0,pawnReset=0,captureReset=0;
void verify(bool value,String message){assertions++;if(!value)throw StateError(message);}
String encode(Object? value)=>jsonEncode(canonicalObject(value));
Map copy(Object? value)=>jsonDecode(jsonEncode(value)) as Map;
void equal(Object? actual,Object? expected,String message)=>verify(encode(actual)==encode(expected),message);
List<String> keys(AuthoritativeBattleState state)=>BattleRulesCore.legalActions(state.view(state.rules.board.turn)).map((a)=>a.key).toList()..sort();
AuthoritativeBattleState apply(AuthoritativeBattleState state,BattleAction action){
  final before=encode(state.toJson()),after=DeckManager.apply(state,action);
  equal(state.toJson(),jsonDecode(before),'accepted action mutated retained input');return after;
}
Map normalized(AuthoritativeBattleState state){final n=copy(state.toJson()),fields=(n['rules']['fen'] as String).split(' ');fields[4]='0';n['rules']['fen']=fields.join(' ');return n;}
void run(Map trace){
  AuthoritativeBattleState initial(String field)=>DeckManager.newBattle(white:parseCards(trace['white']),black:parseCards(trace['black']),board:Board.fromFen(trace[field] as String));
  var low=initial('lowFen'),high=initial('highFen');
  for(final value in trace['actions'] as List){
    final action=BattleAction.fromJson(value as Map);
    equal(keys(low),keys(high),'clock affects available prefix actions');
    low=apply(low,action);high=apply(high,action);prefixTransitions+=2;
    equal(normalized(low),normalized(high),'clock affects complete nonterminal prefix state');
  }
  final native=BattleRulesCore.legalActions(high.view(PieceColor.white));
  equal(native.map((a)=>a.key).toList()..sort(),(trace['finalMoves'] as List).map((a)=>BattleAction.fromJson(a as Map).key).toList()..sort(),'native final full legal set differs');
  verify(high.rules.board.halfmoveClock==149,'actual legal history did not reach 149');
  verify(high.rules.phase==BattlePhase.chess,'card choice was not completely resolved');
  for(final action in native){
    final moveAction=action as ChessMoveAction;
    final geometry=BattleRulesCore.legalMoves(high.rules,PieceColor.white,authorization:high.rules.special).singleWhere((m)=>m.uci==moveAction.uci);
    final lo=apply(low,action),hi=apply(high,action),mover=high.rules.board.squares[geometry.from]!;
    final capture=high.rules.board.squares[geometry.to]!=null||geometry.isEnPassant;
    finalMoves++;
    if(mover.type==PieceType.pawn||capture){equal(hi.toJson(),lo.toJson(),'pawn/capture must reset clock and preserve complete state');if(capture){captureReset++;}else{pawnReset++;}continue;}
    verify(lo.rules.terminal==null,'fixture unexpectedly produced another terminal cause');
    equal(hi.rules.terminal?.toJson(),{'reason':'seventy_five_moves','winner':null,'mateByRestriction':false,'mateBySpecialMove':false,'stalemateByRestriction':false},'75-move terminal');
    verify(hi.rules.phase==BattlePhase.terminal,'terminal phase');equal(keys(hi),<String>[],'terminal has legal actions');
    final expected=copy(lo.toJson()),before=low.toJson(),hr=hi.toJson()['rules'] as Map;
    final er=expected['rules'] as Map,br=before['rules'] as Map;
    final draw=(er['drawCounts']['w'] as int)-(br['drawCounts']['w'] as int);
    er['fen']=hr['fen'];er['phase']='terminal';er['terminal']=hr['terminal'];
    er['handCounts']['w']-=draw;er['deckCounts']['w']+=draw;er['drawCounts']['w']-=draw;
    er['ownTurns']['b']--;er['mana']['b']=br['mana']['b'];er['repetitions']=br['repetitions'];
    final eh=expected['hidden'] as Map,bh=before['hidden'] as Map;
    eh['hands']['w']=bh['hands']['w'];eh['decks']['w']=bh['decks']['w'];
    eh['knowledge']['w']['knownUpcomingCards']=bh['knowledge']['w']['knownUpcomingCards'];
    equal(hi.toJson(),expected,'terminal changes trigger/expiry result or draws/starts another turn: ${trace['id']} ${action.key}');quietThreshold++;
  }
}
void main(){
  final base=File(Platform.script.toFilePath()).parent.path;
  final traces=jsonDecode(File('$base/terminal-threshold-traces.json').readAsStringSync()) as List;
  var passed=0,failed=0;stdout.writeln('TAP version 13');
  for(var i=0;i<traces.length;i++){
    final trace=traces[i] as Map;
    try{run(trace);passed++;stdout.writeln('ok ${i+1} - native reachable threshold: ${trace['id']}');}
    catch(e,stack){failed++;stdout.writeln('not ok ${i+1} - native reachable threshold: ${trace['id']}');stdout.writeln('  ---\n  message: ${jsonEncode(e.toString())}\n  ...');stderr.writeln(stack);}
  }
  stdout.writeln('1..${traces.length}\n# tests ${traces.length}\n# pass $passed\n# fail $failed\n# skipped 0');
  File('$base/terminal-threshold-dart-result.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert({'tests':traces.length,'pass':passed,'fail':failed,'skip':0,'assertions':assertions,'prefixTransitions':prefixTransitions,'finalMoves':finalMoves,'quietThreshold':quietThreshold,'pawnReset':pawnReset,'captureReset':captureReset}));
  if(failed>0)exitCode=1;
}
