cs    = require('control-structures')
redis = require("redis")
rcli  = redis.createClient()

lockconfig = {}
locks = {}
rwlocks = {}
rangelocks = {}
uselocks = ['redislock:keys', '']
# 
# 使用したロック名の記録
# 
regist_uselocks = (lockname)->
  uselocks[1] = lockname
  rcli.SADD uselocks,->return

# 
# ランダムな時間待つ（ロック競合解決のため）
# 
randomwait = (waittimeobj, next)->
  if waittimeobj.time >= lockconfig.waitmax
    waittimeobj.time = lockconfig.waitmin
  if Math.random() > 0.5
    waittimeobj.time *= Math.max(Math.random(),Math.random())*3.0
  else
    waittimeobj.time *= Math.min(Math.random(),Math.random())*3.0
  if waittimeobj.time < lockconfig.waitmin
    waittimeobj.time += lockconfig.waitmin
  setTimeout next, Math.floor(waittimeobj.time-lockconfig.waitmin)

# 
# デバッグ用ログ出力
# 
locklog = (lockobj, message)->
  if lockconfig.log
    logstr = ''
    if /^wait/.test(message) and not lockconfig.logwait
      return
    if /^shrink/.test(message) and not lockconfig.logshrink
      return
    switch lockobj.type
      when 'simple'
        if lockconfig.logsimple
          logstr = lockobj.obj+'['+lockobj.type+']'
        else return
      when 'multi'
        if lockconfig.logsimple
          logstr = lockobj.obj+'['+lockobj.type+']'
        else return
      when 'reader'
        if lockconfig.logrw
          logstr = lockobj.obj+'['+lockobj.type+']'
        else return
      when 'pwr'
        if lockconfig.logrw
          logstr = lockobj.obj+'['+lockobj.type+']'
        else return
      when 'writer'
        if lockconfig.logrw
          logstr = lockobj.obj+'['+lockobj.type+']'
        else return
      when 'rangereader'
        if lockconfig.logrange
          logstr = lockobj.name+'('+lockobj.min+','+lockobj.max+')['+lockobj.type+']'
        else return
      when 'rangepwr'
        if lockconfig.logrange
          logstr = lockobj.name+'('+lockobj.min+','+lockobj.max+')['+lockobj.type+']'
        else return
      when 'rangewriter'
        if lockconfig.logrange
          logstr = lockobj.name+'('+lockobj.min+','+lockobj.max+')['+lockobj.type+']'
        else return
      when 'rangewriter-upgrade'
        if lockconfig.logrange
          logstr = lockobj.name+'('+lockobj.min+','+lockobj.max+')['+lockobj.type+']'
        else return
    
    logstr += ' '+message
    console.log logstr

# 
# RangeLockのユニーク名のリセット
# （RangeLockにはユニーク名が必要だが、延々と足し続けるといつかバグる。
#　手遅れになる前に、良い感じのところで巻き戻す）
# 
resetrangelockname = (lockobj, next)->
  if lockobj.name > 99999999
    rcli.ZADD [lockobj.live, lockobj.name, lockobj.name], (err,reply)->
      rcli.ZRANGE [lockobj.live, 0, 0, 'WITHSCORES'], (err, replies)->
        if replies[1] > 99999999
          rcli.DECRBY [objectname+':uniquename', 99999999], (err,reply)->
            next()
  else
    next()


###
   初期化：前回起動時に使ったロックを全部削除する
###
module.exports.init = init = (config, cleanflag, next)->
  lockconfig = config
  lockconfig.waitmax = lockconfig.waitmax ? 200
  lockconfig.waitmin = lockconfig.waitmin ? 4
  lockconfig['log']       = true
  lockconfig['logwait']   = false
  lockconfig['logshrink'] = false
  lockconfig['logsimple'] = false
  lockconfig['logrw']     = false
  lockconfig['logrange']  = false
  
  if lockconfig.log
    console.log 'init'
  
  if not next?
    if lockconfig.log then console.log 'no next'
    next = -> return
  
  if cleanflag
    rcli.SMEMBERS ['redislock:keys'],(err,replies)->
      replies.push 'redislock:keys'
      rcli.DEL replies,(err,reply)->
        next()
  else
    next()

###
   アンロックは共通
###
# 
# ロックを外す
# 
module.exports.unlock = unlock = (lockobj, next)->
  if not next?
    if lockconfig.log then console.log 'no next'
    next = -> return
  if lockobj?.obj? and lockobj.type?
    switch lockobj.type
      when 'simple'
        rcli.DEL lockobj.obj, (err, reply) ->
          locklog lockobj, 'unlocked'
          next()
      when 'multi'
        if lockobj.obj.length > 0
          rcli.DEL lockobj.obj, (err, reply) ->
            locklog lockobj, 'unlocked'
            next()
        next()
      when 'reader'
        rcli.DECR [lockobj.obj], (err, reply)->
          locklog lockobj, 'unlocked'
          next()
      when 'pwr'
        rcli.DECRBY [lockobj.obj, 50000], (err, reply)->
          locklog lockobj, 'unlocked'
          next()
      when 'writer'
        rcli.DECRBY [lockobj.obj, 100000], (err, reply)->
          locklog lockobj, 'unlocked'
          if lockobj.score == 150000
            delete lockobj.score
            lockobj.type = 'pwr'
          next()
      when 'rangereader'
        locklog lockobj, 'unlocked'
        args = [lockobj.live, lockobj.name]
        rcli.ZREM args, (err, reply)->
          args[0] = lockobj.robj
          args[1] = lockobj.name+':left'
          rcli.ZREM args, (err,reply)->
            args[1] = lockobj.name+':right'
            rcli.ZREM args, (err,reply)->
              #時間が経ったときはユニーク名のリナンバー
              resetrangelockname lockobj, next
      when 'rangepwr'
        locklog lockobj, 'unlocked'
        writerlock lockobj.obj, (metalockobj)->
          args = [lockobj.live, lockobj.name]
          rcli.ZREM args, (err, reply)->
            args[0] = lockobj.pwrobj
            args[1] = lockobj.name+':left'
            rcli.ZREM args, (err,reply)->
              args[1] = lockobj.name+':right'
              rcli.ZREM args, (err,reply)->
                unlock metalockobj,->
                  #時間が経ったときはユニーク名のリナンバー
                  resetrangelockname lockobj, next
      when 'rangewriter'
        locklog lockobj, 'unlocked'
        writerlock lockobj.obj, (metalockobj)->
          args = [lockobj.live, lockobj.name]
          rcli.ZREM args, (err, reply)->
            args[0] = lockobj.wobj
            args[1] = lockobj.name+':left'
            rcli.ZREM args, (err,reply)->
              args[1] = lockobj.name+':right'
              rcli.ZREM args, (err,reply)->
                unlock metalockobj,->
                  #時間が経ったときはユニーク名のリナンバー
                  resetrangelockname lockobj, next
      when 'rangewriter-upgrade'
        locklog lockobj, 'unlocked'
        writerlock lockobj.obj, (metalockobj)->
          args = [lockobj.wobj, lockobj.name+':left']
          rcli.ZREM args, (err,reply)->
            args[1] = lockobj.name+':right'
            rcli.ZREM args, (err,reply)->
              unlock metalockobj,->
                #時間が経ったときはユニーク名のリナンバー
                resetrangelockname lockobj, next
      else
        console.log 'unknown lockobj.type is found! ['+lockobj.type+']'
        process.exit 1
  else
    console.log 'lockobj is empty!'
    process.exit 1


###
   単一ロック
###
# 
# ロックする
# 
module.exports.simplelock = simplelock = (objectname, next)->
  if not next?
    if lockconfig.log then console.log 'no next'
    next = -> return
  waittimeobj = {time: lockconfig.waitmin}
  lockobj = {type: 'simple', obj: objectname+':lock'}
  cs._while []
  ,(_break,_next) ->
    if not (objectname in locks)
      locks[objectname] = true
      regist_uselocks objectname+':lock'
    rcli.SETNX [objectname+':lock', 'ok'], (err, reply) ->
      if reply == 1
        _break()
      else
        locklog lockobj, 'waiting'
        randomwait waittimeobj, _next
  ,->
    locklog lockobj, 'locked'
    next lockobj




###
   複数ロック
###
# 
# ロックする
# 
module.exports.multilock = multilock = (objectarray, next)->
  if not next?
    if lockconfig.log then console.log 'no next'
    next = -> return
  waittimeobj = {time: lockconfig.waitmin}
  lockobj = {}
  lockobj['type'] = 'multi'
  lockobj['obj'] = []
  lockargs = []
  for obj in objectarray
    lockobj.obj.push obj+':lock'
    lockargs.push obj+':lock'
    lockargs.push 'ok'
    if not (obj in locks)
      locks[obj] = true
      regist_uselocks obj+':lock'
  cs._while []
  ,(_break,_next) ->
    rcli.MSETNX lockargs, (err, reply) ->
      if reply == 1
        _break()
      else
        locklog lockobj, 'waiting'
        randomwait waittimeobj, _next
  ,->
    locklog lockobj, 'locked'
    next lockobj



###
   Readerロック
###
module.exports.readerlock = readerlock = (objectname, next)->
  if not next?
    if lockconfig.log then console.log 'no next'
    next = -> return
  waittimeobj = {time: lockconfig.waitmin}
  lockobj = {}
  lockobj['type'] = 'reader'
  lockobj['obj'] = objectname+':rwlock'
  if not (objectname in rwlocks)
    rwlocks[objectname] = true
    regist_uselocks objectname+':rwlock'
  args = [lockobj.obj]
  rcli.INCR args, (err, reply)->
    if reply >= 99999
      rcli.DECR args, (err,reply)->
        cs._while []
        ,(_break,_next) ->
          rcli.GET args, (err,reply)->
            if reply < 99999
              rcli.INCR args, (err, reply)->
                if reply < 99999
                  _break()
                else
                  rcli.DECR args, (err,reply)->
                    locklog lockobj, 'waiting1'
                    randomwait waittimeobj, _next
            else
              locklog lockobj, 'waiting2'
              randomwait waittimeobj, _next
        ,->
          locklog lockobj, 'locked'
          next lockobj
    else
      locklog lockobj, 'locked'
      next lockobj



###
   PreWrite-Readロック
###
module.exports.pwrlock = pwrlock = (objectname, next)->
  if not next?
    if lockconfig.log then console.log 'no next'
    next = -> return
  lockobj = {}
  lockobj['type'] = 'pwr'
  lockobj['obj'] = objectname+':rwlock'
  if not (objectname in rwlocks)
    rwlocks[objectname] = true
    regist_uselocks objectname+':rwlock'
  waittimeobj = {time:lockconfig.waitmin}
  args = [lockobj.obj, 50000]
  rcli.INCRBY args, (err, reply)->
    if reply >= 99999
      rcli.DECRBY args, (err,reply)->
        cs._while []
        ,(_break,_next) ->
          rcli.GET [lockobj.obj], (err,reply)->
            if reply < 49999
              rcli.INCRBY args, (err, reply)->
                if reply < 99999
                  _break()
                else
                  rcli.DECRBY args, (err,reply)->
                    locklog lockobj, 'waiting1'
                    randomwait waittimeobj, _next
            else
              locklog lockobj, 'waiting2'
              randomwait waittimeobj, _next
        ,->
          locklog lockobj, 'locked'
          next lockobj
    else
      locklog lockobj, 'locked'
      next lockobj



###
   Writerロック
###
module.exports.writerlock = writerlock = (objectname_or_lockobj, next)->
  if not next?
    if lockconfig.log then console.log 'no next'
    next = -> return
  basescore = 0
  if objectname_or_lockobj?
    if objectname_or_lockobj.type? and objectname_or_lockobj.type == 'pwr'
      lockobj = objectname_or_lockobj
      lockobj.type = 'writer'
      lockobj['score'] = 150000
      basescore = 50000
    else
      lockobj = {}
      lockobj['type'] = 'writer'
      lockobj['obj'] = objectname_or_lockobj+':rwlock'
      lockobj['score'] = 100000
      if not (objectname_or_lockobj in rwlocks)
        rwlocks[objectname_or_lockobj] = true
        regist_uselocks objectname_or_lockobj+':rwlock'
  else
    console.log 'objectname_or_lockobj is null.'
    process.exit 1
  
  waittimeobj = {time:lockconfig.waitmin}
  replyvalue = 0
  getargs = [lockobj.obj]
  args = [lockobj.obj, 100000]
  rcli.INCRBY args, (err, reply)->
    replyvalue = reply
    cs._ []
    ,(localnext)->
      if replyvalue >= 150000+basescore
        #writerlocked or pwrlocked
        rcli.DECRBY args, (err,reply)->
          cs._while []
          ,(_break,_next)->
            rcli.INCRBY args, (err, reply)->
              replyvalue = reply
              if replyvalue >= 150000+basescore
                rcli.DECRBY args, (err,reply)->
                  locklog lockobj, 'waiting1'
                  randomwait waittimeobj, _next
              else
                _break()
          ,->
            localnext()
      else
        localnext()
    ,->
      waittimeobj.time = lockconfig.waitmin
      if replyvalue >= 100001+basescore
        #readerlocked
        cs._while []
        ,(_break,_next) ->
          rcli.GET getargs, (err,reply)->
            if reply <= 100000+basescore
              _break()
            else
              locklog lockobj, 'waiting2'
              randomwait waittimeobj, _next
        ,->
          locklog lockobj, 'locked'
          next lockobj
      else if replyvalue == 100000+basescore
        #OK
        locklog lockobj, 'locked'
        next lockobj
      else
        #arienai
        console.log 'unknown error (reply = '+reply
        process.exit 1


isconflictrangelock = (targetobj, rangemin, rangemax, threshold, next)->
  if not next?
    if lockconfig.log then console.log 'no next'
    next = -> return
  rcli.ZCOUNT [targetobj, rangemin, rangemax], (err,reply)->
    if reply <= threshold*2
      rcli.ZRANGEBYSCORE [targetobj, '-inf', rangemin], (err,replies)->
        if replies.length == 0
          next false
        else
          tablemem = 0
          for reply in replies
            if /\:left$/.test(reply)
              tablemem += 1
            else if /\:right$/.test(reply)
              tablemem -= 1
            else
              console.log reply+' is an illegal range mark.'
              process.exit 1
          next (tablemem > threshold)
    else
      next true


###
   RangeReaderロック
###
module.exports.rangereaderlock = rangereaderlock = (objectname, rangemin, rangemax, next)->
  if not next?
    if lockconfig.log then console.log 'no next'
    next = -> return
  waittimeobj = {time: lockconfig.waitmin}
  lockobj = {}
  lockobj['type'] = 'rangereader'
  lockobj['name'] = ''
  lockobj['obj'] = objectname+':meta'
  lockobj['min'] = rangemin
  lockobj['max'] = rangemax
  lockobj['robj'] = objectname+':readerlockzset'
  lockobj['pwrobj'] = objectname+':pwrlockzset'
  lockobj['wobj'] = objectname+':writerlockzset'
  lockobj['live'] = objectname+':alivelockzset'
  if not (objectname in rangelocks)
    rangelocks[objectname] = true
    regist_uselocks objectname+':readerlockzset'
    regist_uselocks objectname+':pwrlockzset'
    regist_uselocks objectname+':writerlockzset'
    regist_uselocks objectname+':alivelockzset'
    regist_uselocks objectname+':uniquename'
  
  cs._ []
  ,(localnext)->
    rcli.INCR [objectname+':uniquename'], (err,reply)->
      lockobj.name = reply
      localnext()
  ,->
    cs._while []
    ,(_break,_next)->
      readerlock lockobj.obj,(metalockobj)->
        isconflictrangelock lockobj.wobj, rangemin, rangemax, 0, (isconflict)->
          if not isconflict
            args = [lockobj.robj, rangemin, lockobj.name+':left']
            rcli.ZADD args, (err,reply)->
              args[1] = rangemax
              args[2] = lockobj.name+':right'
              rcli.ZADD args, (err,reply)->
                unlock metalockobj, ->
                  _break()
          else
            unlock metalockobj, ->
              locklog lockobj, 'waiting'
              randomwait waittimeobj, _next
    ,->
      locklog lockobj, 'locked'
      next lockobj


###
   RangeReaderロックの対象を縮小する
###
module.exports.rangereaderlock_shrink = rangereaderlock_shrink = (lockobj, rangemin, rangemax, next)->
  if not next?
    if lockconfig.log then console.log 'no next'
    next = -> return
  if lockobj.type == 'rangereader' and lockobj.min <= rangemin and rangemin <= rangemax and rangemax <= lockobj.max
    args = [lockobj.robj, rangemin, lockobj.name+':left']
    rcli.ZADD args, (err,reply)->
      args[1] = rangemax
      args[2] = lockobj.name+':right'
      rcli.ZADD args, (err,reply)->
        lockobj.min = rangemin
        lockobj.max = rangemax
        locklog lockobj, 'shrinked'
        next lockobj
  else
    console.log 'err'
    process.exit 1



###
   RangePWRロック
###
module.exports.rangepwrlock = rangepwrlock = (objectname, rangemin, rangemax, next)->
  if not next?
    if lockconfig.log then console.log 'no next'
    next = -> return
  waittimeobj = {time: lockconfig.waitmin}
  lockobj = {}
  lockobj['type'] = 'rangepwr'
  lockobj['name'] = ''
  lockobj['obj'] = objectname+':meta'
  lockobj['min'] = rangemin
  lockobj['max'] = rangemax
  lockobj['robj'] = objectname+':readerlockzset'
  lockobj['pwrobj'] = objectname+':pwrlockzset'
  lockobj['wobj'] = objectname+':writerlockzset'
  lockobj['live'] = objectname+':alivelockzset'
  if not (objectname in rangelocks)
    rangelocks[objectname] = true
    regist_uselocks objectname+':readerlockzset'
    regist_uselocks objectname+':pwrlockzset'
    regist_uselocks objectname+':writerlockzset'
    regist_uselocks objectname+':alivelockzset'
    regist_uselocks objectname+':uniquename'
  
  cs._ []
  ,(localnext)->
    rcli.INCR [objectname+':uniquename'], (err,reply)->
      lockobj.name = reply
      localnext()
  ,->
    cs._while []
    ,(_break,_next)->
      pwrlock lockobj.obj,(metalockobj)->
        isconflictrangelock lockobj.pwrobj, lockobj.min, lockobj.max, 0, (isconflict)->
          if not isconflict
            isconflictrangelock lockobj.wobj, lockobj.min, lockobj.max, 0, (isconflict)->
              if not isconflict
                writerlock metalockobj,(metalockobj)->
                  args = [lockobj.pwrobj, lockobj.min, lockobj.name+':left']
                  rcli.ZADD args, (err,reply)->
                    args[1] = lockobj.max
                    args[2] = lockobj.name+':right'
                    rcli.ZADD args, (err,reply)->
                      unlock metalockobj, ->
                        unlock metalockobj, ->
                          _break()
              else
                unlock metalockobj, ->
                  locklog lockobj, 'waiting'
                  randomwait waittimeobj, _next
          else
            unlock metalockobj, ->
              randomwait waittimeobj, _next
    ,->
      locklog lockobj, 'locked'
      next lockobj



###
   RangePWRロックの対象を縮小する
###
module.exports.rangepwrlock_shrink = rangepwrlock_shrink = (lockobj, rangemin, rangemax, next)->
  if not next?
    if lockconfig.log then console.log 'no next'
    next = -> return
  if lockobj.type == 'rangepwr' and lockobj.min <= rangemin and rangemin <= rangemax and rangemax <= lockobj.max
    args = [lockobj.pwrobj, rangemin, lockobj.name+':left']
    rcli.ZADD args, (err,reply)->
      args[1] = rangemax
      args[2] = lockobj.name+':right'
      rcli.ZADD args, (err,reply)->
        lockobj.min = rangemin
        lockobj.max = rangemax
        locklog lockobj, 'shrinked'
        next lockobj
  else
    console.log 'err'
    process.exit 1



###
   RangeWriterロック
###
module.exports.rangewriterlock = rangewriterlock = (objectname_or_lockobj, rangemin, rangemax, next)->
  if not next?
    if lockconfig.log then console.log 'no next'
    next = -> return
  waittimeobj = {time: lockconfig.waitmin}
  lockobj = {}
  basename = ''
  if not objectname_or_lockobj?
    console.log 'error'
    process.exit 1
  else
    cs._ []
    ,(localnext1)->
      if objectname_or_lockobj.type? and objectname_or_lockobj.type == 'rangepwr'
        #rangepwrlockの内部にrangewritelockを作る場合
        lockobj['obj'] = objectname_or_lockobj.obj
        basename = objectname_or_lockobj.obj.replace(/\:meta$/, '')
        lockobj['type'] = 'rangewriter-upgrade'
        pwrmin = objectname_or_lockobj.min
        pwrmax = objectname_or_lockobj.max
        if pwrmin <= rangemin and rangemin <= rangemax and rangemax <= pwrmax
          lockobj['min'] = rangemin
          lockobj['max'] = rangemax
          localnext1 basename
        else
          console.log 'error'
          process.exit 1
      else
        #いきなりrangewritelockを作る場合
        lockobj['obj'] = objectname_or_lockobj+':meta'
        basename = objectname_or_lockobj
        lockobj['type'] = 'rangewriter'
        lockobj['min'] = rangemin
        lockobj['max'] = rangemax
        localnext1 basename
    ,(localnext2, basename)->
      lockobj['robj'] = basename+':readerlockzset'
      lockobj['pwrobj'] = basename+':pwrlockzset'
      lockobj['wobj'] = basename+':writerlockzset'
      lockobj['live'] = basename+':alivelockzset'
      if not (basename in rangelocks)
        rangelocks[basename] = true
        regist_uselocks basename+':readerlockzset'
        regist_uselocks basename+':pwrlockzset'
        regist_uselocks basename+':writerlockzset'
        regist_uselocks basename+':alivelockzset'
        regist_uselocks basename+':uniquename'
      rcli.INCR [basename+':uniquename'], (err,reply)->
        lockobj.name = reply
        if objectname_or_lockobj.type? and objectname_or_lockobj.type == 'rangepwr'
          #rangepwrlockの内部にrangewritelockを作る場合、
          #rangepwrlockやrangewriterlockとの競合は既に排除されているので、
          #ロックの数を揃えるためのpwrlockをかけるだけで先へ進む
          pwrlock lockobj.obj,(metalockobj)->
            localnext2 metalockobj
        else
          #rangepwrlockやrangewriterlockとの競合をテストして、競合しなくなるまでリトライ
          cs._while []
          ,(_break,_next)->
            pwrlock lockobj.obj,(metalockobj)->
              #writerともpwrとも衝突チェックして、外れるまでゼロから繰り返し
              isconflictrangelock lockobj.pwrobj, lockobj.min, lockobj.max, 0, (isconflict)->
                if not isconflict
                  isconflictrangelock lockobj.wobj, lockobj.min, lockobj.max, 0, (isconflict)->
                    if not isconflict
                      _break metalockobj
                    else
                      unlock metalockobj, ->
                        locklog lockobj, 'waiting1'
                        randomwait waittimeobj, _next
                else
                  unlock metalockobj, ->
                    locklog lockobj, 'waiting2'
                    randomwait waittimeobj, _next
          ,(metalockobj)->
            localnext2 metalockobj
    ,(_dummynext, metalockobj)->
      #writerともpwrとも衝突していないので、readerを無視してロックをかけてしまう
      writerlock metalockobj,(metalockobj)->
        args = [lockobj.wobj, lockobj.min, lockobj.name+':left']
        rcli.ZADD args, (err,reply)->
          args[1] = lockobj.max
          args[2] = lockobj.name+':right'
          rcli.ZADD args, (err,reply)->
            unlock metalockobj, ->
              unlock metalockobj, ->
                #重複するrangereadlockが外れるのを待つ
                waittimeobj.time = lockconfig.waitmin
                cs._while []
                ,(_break,_next)->
                  isconflictrangelock lockobj.robj, lockobj.min, lockobj.max, 0, (isconflict)->
                    if not isconflict
                      _break()
                    else
                      randomwait waittimeobj, _next
                ,->
                  locklog lockobj, 'locked'
                  next lockobj



###
   RangeWriterロックの対象を縮小する
###
module.exports.rangewriterlock_shrink = rangewriterlock_shrink = (lockobj, rangemin, rangemax, next)->
  if not next?
    if lockconfig.log then console.log 'no next'
    next = -> return
  if lockobj.type == 'rangewriter' and lockobj.min <= rangemin and rangemin <= rangemax and rangemax <= lockobj.max
    args = [lockobj.wobj, rangemin, lockobj.name+':left']
    rcli.ZADD args, (err,reply)->
      args[1] = rangemax
      args[2] = lockobj.name+':right'
      rcli.ZADD args, (err,reply)->
        lockobj.min = rangemin
        lockobj.max = rangemax
        locklog lockobj, 'shrinked'
        next lockobj
  else
    console.log 'err'
    process.exit 1


