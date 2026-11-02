import 'dart:convert';
import 'dart:io';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';

const out='/workspace/luno-review/bug-audit-round4/rules';
Map context={};
final stats=<String,dynamic>{'states':0,'sourceLegalActions':0,'cards':<String>[],
  'rename':{'states':0,'branches':0,'assertions':0},
  'clock':{'states':0,'changedStates':0,'branches':0,'assertions':0}};
dynamic copy(dynamic v)=>jsonDecode(jsonEncode(v));
dynamic canonical(dynamic v){
 if(v is List)return v.map(canonical).toList();
 if(v is Map){final keys=v.keys.cast<String>().toList()..sort();return {for(final k in keys)k:canonical(v[k])};}
 return v;
}
String encoded(dynamic v)=>jsonEncode(canonical(v));
void eq(dynamic a,dynamic b,String message,String kind){
 stats[kind]['assertions']++;
 if(encoded(a)!=encoded(b))throw StateError('$message\ncontext=${jsonEncode(context)}\nactual=${encoded(a)}\nexpected=${encoded(b)}');
}
dynamic mapIds(dynamic value,Map pieces,Map effects,[String key='']){
 if(value is! Map&&value is! List){
  if(value is String&&['pieceId','pieceIds','movedPawns'].contains(key))return pieces[value]??value;
  if(value is String&&key=='id')return effects[value]??value;
  return value;
 }
 if(value is List)return value.map((v)=>mapIds(v,pieces,effects,key)).toList();
 final result=<String,dynamic>{};
 for(final k in (value as Map).keys){
  final v=value[k];
  if(k=='repetitions'){
   result[k]={for(final fp in (v as Map).keys) remapFingerprint(fp,pieces,effects):v[fp]};
  }else result[k]=mapIds(v,pieces,effects,k);
 }
 return result;
}
String remapFingerprint(String fp,Map pieces,Map effects){
 try{return jsonEncode(mapIds(jsonDecode(fp),pieces,effects));}catch(_){return fp;}
}
Map actionIds(Map a,Map effects){final b=copy(a) as Map;if(b['type']=='play'&&['purify','break_seal'].contains(b['card']))b['target']=effects[b['target']]??b['target'];return b;}
Map clocks(Map s,Map offsets,[int direction=1]){
 final b=copy(s) as Map;
 for(final c in ['w','b'])b['rules']['ownTurns'][c]+=direction*offsets[c];
 for(final m in b['rules']['modifiers'])m['ownTurn']+=direction*offsets[m['responseSide']];
 return b;
}
List<String> keys(AuthoritativeBattleState s)=>(BattleRulesCore.legalActions(s.view(s.rules.board.turn)).map((a)=>a.key).toList()..sort());
void run(List rows,String kind){
 for(final raw in rows){final row=raw as Map;
  context={'kind':kind,'label':row['label']};
  final state=AuthoritativeBattleState.fromJson(row['state']);
  final stateJson=state.toJson(),before=encoded(stateJson);
  final pieces=kind=='rename'?row['pieces'] as Map:{},effects=kind=='rename'?row['effects'] as Map:{};
  final invPieces={for(final e in pieces.entries)e.value:e.key},invEffects={for(final e in effects.entries)e.value:e.key};
  final transformedJson=kind=='rename'?mapIds(stateJson,pieces,effects):clocks(stateJson,row['offsets']);
  Map restored(Map s)=>kind=='rename'?mapIds(s,invPieces,invEffects) as Map:clocks(s,row['offsets'],-1);
  final transformed=AuthoritativeBattleState.fromJson(transformedJson);
  final transformedBefore=encoded(transformed.toJson());
  eq(restored(transformed.toJson()),stateJson,'transformation invertibility',kind);
  final actions=BattleRulesCore.legalActions(state.view(state.rules.board.turn));
  final expectedActions=actions.map((a)=>BattleAction.fromJson(actionIds(a.toJson(),effects)).key).toList()..sort();
  eq(keys(transformed),expectedActions,'complete transformed legal set',kind);
  stats[kind]['states']++;
  if(kind=='clock'&&(row['offsets']['w']>0||row['offsets']['b']>0))stats[kind]['changedStates']++;
  for(final action in actions){
   context={'kind':kind,'label':row['label'],'action':action.toJson()};
   final next=DeckManager.apply(state,action);
   final changed=DeckManager.apply(transformed,BattleAction.fromJson(actionIds(action.toJson(),effects)));
   eq(restored(changed.toJson()),next.toJson(),'complete transformed authoritative transition',kind);
   final nextKeys=BattleRulesCore.legalActions(next.view(next.rules.board.turn)).map((a)=>BattleAction.fromJson(actionIds(a.toJson(),effects)).key).toList()..sort();
   eq(keys(changed),nextKeys,'complete transformed successor legal set',kind);
   eq(encoded(state.toJson()),before,'retained source input',kind);
   eq(encoded(transformed.toJson()),transformedBefore,'retained transformed input',kind);
   stats[kind]['branches']++;
  }
 }
 stdout.writeln('$kind PASS states=${stats[kind]['states']} branches=${stats[kind]['branches']} assertions=${stats[kind]['assertions']}');
}
void main(){
 try{
  final rows=jsonDecode(File('$out/round4_rules_states.json').readAsStringSync()) as List;
  final cards=<String>{};
  for(final raw in rows){final row=raw as Map;final state=AuthoritativeBattleState.fromJson(row['state']);final actions=BattleRulesCore.legalActions(state.view(state.rules.board.turn));stats['states']++;stats['sourceLegalActions']+=actions.length;for(final action in actions)if(action is PlayCardAction)cards.add(action.card.wire);}
  stats['cards']=cards.toList()..sort();
  run(rows,'rename');run(rows,'clock');
  File('$out/metamorphic-dart-result.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert({'status':'PASS','stats':stats})}\n');
 }catch(error,stack){
  File('$out/metamorphic-dart-result.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert({'status':'FAIL','stats':stats,'context':context,'error':error.toString()})}\n');
  stderr.writeln(error);stderr.writeln(stack);exitCode=1;
 }
}
