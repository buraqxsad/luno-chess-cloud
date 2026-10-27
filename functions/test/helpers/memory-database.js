'use strict';

const {getDatabase}=require('firebase-admin/database');
const copy=value=>value==null?null:structuredClone(value);

function memoryDatabase(t,seed={},options={}){
  const data=copy(seed),writes=[],transactions=[],reads=new Map(),counts=new Map(),pushes=new Map();
  function read(path){return path.split('/').filter(Boolean).reduce((value,key)=>value&&value[key],data)??null;}
  function write(path,value){
    const keys=path.split('/').filter(Boolean),leaf=keys.pop();
    if(!leaf)throw new Error('Use update for root writes in the test database.');
    let target=data;
    const parents=[];
    for(const key of keys){parents.push([target,key]);target=target[key]||(target[key]={});}
    if(value==null)delete target[leaf];else target[leaf]=copy(value);
    for(const [parent,key] of parents.reverse()){
      if(parent[key]&&typeof parent[key]==='object'&&Object.keys(parent[key]).length===0)delete parent[key];else break;
    }
  }
  function compareKeys(a,b){
    const integer=key=>/^-?\d+$/.test(key)&&Number(key)>=-2147483648&&Number(key)<=2147483647?Number(key):null;
    const ai=integer(a),bi=integer(b);
    if(ai!==null&&bi!==null)return ai-bi||a.length-b.length||a.localeCompare(b,'en');
    if(ai!==null)return -1;if(bi!==null)return 1;
    return a<b?-1:a>b?1:0;
  }
  function snapshot(value,key=null,keys=Object.keys(value||{})){
    return {key,val:()=>copy(value),exists:()=>value!=null,numChildren:()=>Object.keys(value||{}).length,
      forEach(visitor){for(const child of keys){if(visitor(snapshot(value[child],child))===true)return true;}return false;}};
  }
  function reference(path='',query={}){
    return {
      child(key){return reference([path,key].filter(Boolean).join('/'));},
      orderByKey(){return reference(path,{...query,byKey:true});},
      startAfter(key){return reference(path,{...query,after:key});},
      orderByValue(){return reference(path,{...query,byValue:true});},
      orderByChild(child){return reference(path,{...query,child});},
      equalTo(value){return reference(path,{...query,equal:value});},
      limitToFirst(limit){return reference(path,{...query,limit});},
      async once(event){
        if(event!=='value')throw new Error('Only one-time value reads are modeled.');
        return this.get();
      },
      async get(){
        let value=copy(read(path));
        let orderedKeys;
        if(query.byValue||query.child)value=Object.fromEntries(Object.entries(value||{}).filter(([,item])=>(query.byValue?item:query.child.split('/').reduce((current,key)=>current&&current[key],item))===query.equal));
        if(query.byKey){
          const rows=Object.entries(value||{}).sort(([a],[b])=>compareKeys(a,b)).filter(([key])=>query.after==null||compareKeys(key,query.after)>0);
          orderedKeys=rows.slice(0,query.limit||Infinity).map(([key])=>key);
          value=Object.fromEntries(rows.slice(0,query.limit||Infinity));
        }else if(query.limit)value=Object.fromEntries(Object.entries(value||{}).slice(0,query.limit));
        const count=(reads.get(path)||0)+1;reads.set(path,count);
        if(options.afterRead)options.afterRead(path,count,{read,write});
        return snapshot(value,path.split('/').filter(Boolean).at(-1)||null,orderedKeys);
      },
      async transaction(update,onComplete,applyLocally){
        const count=(counts.get(path)||0)+1;counts.set(path,count);
        transactions.push({path,applyLocally,count});
        if(options.beforeTransaction)options.beforeTransaction(path,count,{read,write});
        let next;
        if(options.cold!==false){
          next=update(null);
          if(next===undefined)return {committed:false,snapshot:snapshot(null)};
        }
        next=update(copy(read(path)));
        if(options.retry)next=options.retry(path,count,update,next,{read,write});
        if(next!==undefined){write(path,next);writes.push({path,kind:'transaction',value:copy(next)});}
        if(options.afterTransaction)options.afterTransaction(path,count,{read,write});
        return {committed:next!==undefined,snapshot:snapshot(read(path))};
      },
      async set(value){if(options.beforeWrite)options.beforeWrite(path,'set',{read,write});write(path,value);writes.push({path,kind:'set'});if(options.afterWrite)options.afterWrite(path,'set',{read,write});},
      async remove(){if(options.beforeWrite)options.beforeWrite(path,'remove',{read,write});write(path,null);writes.push({path,kind:'remove'});if(options.afterWrite)options.afterWrite(path,'remove',{read,write});},
      async update(values){
        if(options.beforeWrite)options.beforeWrite(path,'update',{read,write,values});
        for(const [key,value] of Object.entries(values))write([path,key].filter(Boolean).join('/'),value);
        writes.push({path,kind:'update'});
      },
      async push(value){
        const count=(pushes.get(path)||0)+1;pushes.set(path,count);
        const key=count===1?'entry':'entry'+count,child=path+'/'+key;
        if(options.beforeWrite)options.beforeWrite(child,'push',{read,write});
        write(child,value);writes.push({path:child,kind:'push'});
        if(options.afterWrite)options.afterWrite(child,'push',{read,write});
        return {key};
      },
    };
  }
  t.mock.method(getDatabase(),'ref',reference);
  return {data,read,write,writes,transactions};
}

module.exports={memoryDatabase};
