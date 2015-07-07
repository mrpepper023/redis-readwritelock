redislock = require('../lib/redis-readwritelock')



###
---------------------------------------------
   test
---------------------------------------------
###


randsleep = (next)->
  setTimeout next, Math.floor(Math.random()*1000)


testA = (num)->
  randsleep ->
    redislock.simplelock 'test', (lockobj)->
      randsleep ->
        console.log 'testA'+num
        redislock.unlock lockobj, ->
          return

testB = (num)->
  randsleep ->
    redislock.simplelock 'test2', (lockobj)->
      randsleep ->
        console.log 'testB'+num
        redislock.unlock lockobj, ->
          return

testC = (num)->
  randsleep ->
    redislock.simplelock 'test3', (lockobj)->
      randsleep ->
        console.log 'testC'+num
        redislock.unlock lockobj, ->
          return

testD = (num)->
  randsleep ->
    redislock.multilock ['test','test2','test3'], (lockobj)->
      randsleep ->
        console.log 'testD'+num
        redislock.unlock lockobj, ->
          return

testrwA = (num)->
  randsleep ->
    redislock.readerlock 'test', (lockobj)->
      randsleep ->
        console.log 'testA'+num
        redislock.unlock lockobj, ->
          return

testrwB = (num)->
  randsleep ->
    redislock.readerlock 'test', (lockobj)->
      randsleep ->
        console.log 'testB'+num
        redislock.unlock lockobj, ->
          randsleep ->
            randsleep ->
              redislock.readerlock 'test', (lockobj)->
                randsleep ->
                  console.log 'testBB'+num
                  redislock.unlock lockobj, ->
                    randsleep ->
                      randsleep ->
                        redislock.readerlock 'test', (lockobj)->
                          randsleep ->
                            console.log 'testBBB'+num
                            redislock.unlock lockobj, ->
                              randsleep ->
                                randsleep ->
                                  redislock.readerlock 'test', (lockobj)->
                                    randsleep ->
                                      console.log 'testBBBB'+num
                                      redislock.unlock lockobj, ->
                                        return

testrwC = (num)->
  randsleep ->
    redislock.pwrlock 'test', (lockobj)->
      randsleep ->
        redislock.writerlock lockobj, (lockobj)->
          console.log 'testC'+num+':'+lockobj.score
          redislock.unlock lockobj, ->
            randsleep ->
              redislock.unlock lockobj, ->
                return

testrwD = (num)->
  randsleep ->
    redislock.writerlock 'test', (lockobj)->
      console.log 'testD'+num
      redislock.unlock lockobj, ->
        return


testrangeA = (num)->
  randsleep ->
    redislock.rangereaderlock 'test', 0, 2, (lockobj)->
      randsleep ->
        console.log 'testA'+num
        redislock.unlock lockobj, ->
          return

testrangeB = (num)->
  randsleep ->
    redislock.rangereaderlock 'test', 0, 1, (lockobj)->
      randsleep ->
        console.log 'testB'+num
        redislock.unlock lockobj, ->
          randsleep ->
            randsleep ->
              redislock.rangereaderlock 'test', 1, 2, (lockobj)->
                randsleep ->
                  console.log 'testBB'+num
                  redislock.unlock lockobj, ->
                    randsleep ->
                      randsleep ->
                        redislock.rangereaderlock 'test', 2, 3,  (lockobj)->
                          randsleep ->
                            console.log 'testBBB'+num
                            redislock.unlock lockobj, ->
                              randsleep ->
                                randsleep ->
                                  redislock.rangereaderlock 'test', 1, 2, (lockobj)->
                                    randsleep ->
                                      console.log 'testBBBB'+num
                                      redislock.unlock lockobj, ->
                                        return

testrangeC = (num)->
  randsleep ->
    redislock.rangepwrlock 'test', 0.5, 2.0, (lockobj)->
      randsleep ->
        redislock.rangewriterlock lockobj, 1.2, 1.8, (wlockobj)->
          console.log 'testC'+num
          redislock.unlock wlockobj, ->
            randsleep ->
              redislock.unlock lockobj, ->
                return

testrangeD = (num)->
  randsleep ->
    redislock.rangewriterlock 'test', 2.2, 2.3, (lockobj)->
      console.log 'testD'+num
      redislock.unlock lockobj, ->
        return



redislock.init {
  logwait: no
  logshrink: no
  logsimple: yes
  logrw: yes
  logrange: yes
},->
  switch 1
    when 1
      for i in [0..5]
        testA i
        testB i
        testC i
        testD i
    when 2
      for i in [0..5]
        testrwA i
        testrwB i
        testrwC i
        testrwD i
    when 3
      for i in [0..5]
        testrangeA i
        testrangeB i
        testrangeC i
        testrangeD i

