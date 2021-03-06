# run this script to generate a submission file.
source('prepare_data.r')
source('fun.r')
library(xgboost)

train_dir="/Downloads/season_1/training_data/"
test_dir="/Downloads/season_1/test_set_1/"
train.dat=prepare_train_data(train_dir)
test.dat=prepare_test_data(test_dir)
save(train.dat,test.dat,file='didi.dat')# for future use

train.gap=train.dat$gap
test.gap=test.dat$gap

# use poi
poi.dt=data.table(train.dat$poi.dat)
poi.dt[,id:=.I]
setkey(poi.dt,'id')
setkey(train.gap,'id')
setkey(test.gap,'id')
train.gap=train.gap[poi.dt]
test.gap=test.gap[poi.dt]

# id to dummy variables
for(i in 1:66){
train.gap[,(paste0('id_',i)):=as.numeric(id==i)]
test.gap[,(paste0('id_',i)):=as.numeric(id==i)]
}

vars.id=sapply(c(1:66),function(x) paste0('id_',x))

# train xgb model
# without poi variables for now
vars=c("gap_past_1"      ,        "gap_past_2"     ,         "gap_past_3"           ,  
        #"id"        ,                  
        "placed_past_1"   ,        "placed_past_2"      ,       "placed_past_3"   ,               
         "timeslice"  ,                  
         "total_past_1"           ,"total_past_2"     ,       "total_past_3"     ,       
         "traffic_l1_past1"   ,     "traffic_l2_past1"  ,     "traffic_l3_past1"  ,      "traffic_l4_past1"  , 
         "traffic_l1_past2" ,       "traffic_l2_past2"    ,    "traffic_l3_past2"   ,    "traffic_l4_past2"   ,  
         "traffic_l1_past3"   ,     "traffic_l2_past3"  ,      "traffic_l3_past3"     ,   "traffic_l4_past3"    ,   
         "weather_condition_past1", "weather_condition_past2", "weather_condition_past3",
         "weather_pm25_past1"  ,    "weather_pm25_past2"   ,   "weather_pm25_past3"   , 
         "weather_temp_past1"  ,    "weather_temp_past2" ,     "weather_temp_past3"   , 
         "weekday" ,vars.id,colnames(poi.dt))[1:300]
         
train=sample.timeslot(T)# T means using the exact timeslots for leaderboard; F meas using random timeslots
train.dt=train.gap[day %in% train[[1]] & timeslice>30 ,c(vars,'gap'),with=F]
test.dt=train.gap[day %in% train[[2]] & timeslice %in% train[[3]],c(vars,'gap'),with=F]

dtrain=xgb.DMatrix(data=data.matrix(train.dt[,vars,with=F]),label=train.dt$gap,missing=NA)
dval=xgb.DMatrix(data=data.matrix(test.dt[,vars,with=F]),label=test.dt$gap,missing=NA)
dtest=xgb.DMatrix(data=data.matrix(test.gap[,vars,with=F]),
                  missing=NA)
watchlist = list(test=dval,train=dtrain)
params = list(booster='gbtree',
              #objective='reg:linear',
              objective=mapeObj3,
              eval_metric=evalMAPE2,           
              lambda=1,
              subsample=0.7,
              colsample_bytree=0.6,
              #min_child_weight=minchildweight,
              max_depth=8,
              eta=0.02
)

#set.seed(1)
fit = xgb.train(data=dtrain, nround=10000, watchlist=watchlist,params=params,early.stop.round = 50,maximize = F)
imp.features=xgb.importance(model=fit,feature_names = vars)
# train with all data
dat.train=train.gap[day!=as.Date('2016-01-01') & timeslice>30,]
dtrain.all=xgb.DMatrix(data=data.matrix(dat.train[,vars,with=F]),label=dat.train$gap,missing=NA)
fit.new = xgb.train(data=dtrain.all, nround=fit$bestInd,params=params,watchlist = list(train=dtrain.all))

pred=predict(fit.new,newdata = dtest)
pred[pred<1]=1
write.sub(id=test.dat$gap$id,day = test.dat$gap$day,timeslice = test.dat$gap$timeslice,pred,'rnorm.csv')
