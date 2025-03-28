To run, simply move to the akash directory and run config-akash.sh.


ensure you have proper akash cli keys configured. 

current setup does not create key for user, only directs them how to. 

Use the following commands:

### Move to Akash directory
```bash
cd ./cloud/akash
```
### create new config file from config.example.sh
```bash
cp config.example.sh config.sh
```
Now configure your enviornmental variables. Current on chain environmental variables configured for arbitrum-sepolia. 


### Run deployment script.
```bash
./config-akash.sh
```
