const fs = require('node:fs');
const path = require('node:path');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const folder = path.resolve(__dirname, '../qa/source-audit/screens');
const groups = {
  core: ['startup','home','play','collection'],
  hubs: ['profile','missions','shop','settings'],
  battle: ['battle-initial','battle-after-draw','own-draw-mid','opponent-draw'],
  states: ['opponent-public-cards','result','shop-gems','friends-empty'],
};
async function main() {
  for(const language of ['tr','en'])for(const [group,names] of Object.entries(groups)){
    const composite=[];
    for(let i=0;i<names.length;i++){
      const name=names[i]+'-'+language;
      const tile=await sharp(path.join(folder,name+'.png')).resize(234,507,{fit:'contain',background:'#080f18'}).png().toBuffer();
      const label=Buffer.from(`<svg width="234" height="28"><rect width="234" height="28" fill="#080f18"/><text x="8" y="19" font-family="Arial" font-size="13" fill="#f3efe5">${name}</text></svg>`);
      composite.push({input:label,left:i*234,top:0},{input:tile,left:i*234,top:28});
    }
    await sharp({create:{width:936,height:535,channels:4,background:'#080f18'}}).composite(composite).png().toFile(path.join(folder,`contact-${group}-${language}.png`));
  }
  console.log('Eight TR/EN contact sheets created from actual Flutter renders.');
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
