const { chromium } = require('playwright');
(async()=>{const b=await chromium.launch(); const pg=await b.newPage({viewport:{width:1300,height:900},deviceScaleFactor:2});
for (const [f,o] of [['p1','1-trip-summary'],['p2','2-share-cards'],['p3','3-heatmap-free-vs-pro']]){
 await pg.goto('file://'+process.cwd()+'/'+f+'.html'); await pg.waitForTimeout(400);
 await pg.screenshot({path:'/home/user/mockups/'+o+'.png', fullPage:true});}
await b.close();})();
