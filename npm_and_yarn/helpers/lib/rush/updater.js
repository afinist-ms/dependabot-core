const fs = require("fs");
const path = require("path")
var exec = require('child_process').exec, child;

async function runRushUpdate(rootPath, shrinkwrapFilePath){
    
    return new Promise(resolve => {
    
        exec('node common/scripts/install-run-rush.js update -p --no-link --bypass-policy', function(a,b,c) {
            const updateFileContent = fs.readFileSync(path.join(rootPath, shrinkwrapFilePath)).toString()
            // return { shrinkwrapFilePath: updateFileContent };
            return resolve(updateFileContent) ;
        });
    },
    //  TODO: Handle error as well 
    () => {});
}

module.exports = { runRushUpdate }