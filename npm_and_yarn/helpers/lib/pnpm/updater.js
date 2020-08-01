const fs = require("fs");
const path = require("path")
var exec = require('child_process').exec, child;

async function updateLockFile(rootPath, lockFilePath){

    return new Promise(resolve => {    
        exec('npx pnpm install --lockfile-only --recursive', function(error, stdout, stderr) {

            if (error) {
                console.log(`error: ${error.message}`);
                console.log(`stderr: ${stderr}`);
                console.log(`stdout: ${stdout}`);


                // throw error;
                // throw error;
                return resolve(null);
            }

            // if (stderr) {
            //     console.log(`stderr: ${stderr}`);
            //     return;
        
            // }
            // console.log(`stdout: ${stdout}`);

            const updateFileContent = fs.readFileSync(path.join(rootPath, lockFilePath)).toString()
            return resolve(updateFileContent);
        });
    },
    //  TODO: Handle error as well 
    () => {});
}
module.exports = { updateLockFile }
