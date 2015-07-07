# redis-readwritelock

readwritelock with redis.

# Usage

## General Functions

### init(config, cleanflag, next)

config is an object included configuration parameters.
cleanflag is a flag whether it clean zombie lock keys in your redis database or not.
next() is called with no arguments.
it create lockconfig, and clean zombie lock keys.

### unlock(lockobj, next)

lockobj is an argument of a next function of lock functions.
next() is called with no arguments.

## Simple Lock Functions

### simplelock(objectname, next)

objectname is a string.
next() is called with an argument 'lockobj' for unlock the lock.

### multilock(objectarray, next)

objectarray is an array of strings.
next() is called with an argument 'lockobj' for unlock the lock.

## Read-Write-Lock Functions

### readerlock(objectname, next)

objectname is a string.
next() is called with an argument 'lockobj' for unlock the lock.

### pwrlock(objectname, next)

objectname is a string.
next() is called with an argument 'lockobj' for unlock the lock.
pwrlock means 'prewrite read lock'. this is a sort of a read lock. but pwrlock is never caught any other pwrlocks or writerlocks, and you can upgrade it to writerlock without unlock it.

### writerlock(objectname_or_lockobj, next)

objectname_or_lockobj is a string or an object of pwrlock.
next() is called with an argument 'lockobj' for unlock the lock.

## Range Read-Write-Lock Functions

### rangereaderlock(objectname, rangemin, rangemax, next)

objectname is a string.
rangemin is a real number.
rangemax is a real number.
next() is called with an argument 'lockobj' for unlock the lock.

### rangepwrlock(objectname, rangemin, rangemax, next)

objectname is a string.
rangemin is a real number.
rangemax is a real number.
next() is called with an argument 'lockobj' for unlock the lock.

### rangewriterlock(objectname_or_lockobj, rangemin, rangemax, next)

objectname is a string.
rangemin is a real number.
rangemax is a real number.
next() is called with an argument 'lockobj' for unlock the lock.

## Range Read-Write-Lock: Shrink Range Functions

### rangereaderlock_shrink(lockobj, rangemin, rangemax, next)

lockobj is an object of rangereaderlock.
rangemin is a real number.
rangemax is a real number.
next() is called with an argument 'lockobj' for unlock the lock.

### rangepwrlock_shrink(lockobj, rangemin, rangemax, next)

lockobj is an object of rangepwrlock.
rangemin is a real number.
rangemax is a real number.
next() is called with an argument 'lockobj' for unlock the lock.

### rangewriterlock_shrink(lockobj, rangemin, rangemax, next)

lockobj is an object of rangewriterlock.
rangemin is a real number.
rangemax is a real number.
next() is called with an argument 'lockobj' for unlock the lock.

