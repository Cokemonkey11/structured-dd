
//*     API:
//* boolean ADD_ALL_UNITS: If enabled, a trigger turns on which automatically
//*     registers all units in the map.
//* integer BUCKET_SIZE: How many units to add to each 'bucket' - a larger
//*     bucket will have their trigger refresh less frequently but will be
//*     more computationally expensive. A good starting value is about 20.
//* real PER_CLEANUP_TIMEOUT: How many seconds to wait in between each
//*     scan for empty buckets. This value should be lower if units die often
//*     in your map. A good starting value is about 60.
//* static method addHandler: Registers a callback function to the generic
//*     unit damage event. Example: call StructuredDD.addHandler(function h)
//* static method add: Adds a unit to a bucket. If ADD_ALL_UNITS is enabled,
//*     this method need not be used.
library StructuredDD
    globals

        //<< BEGIN SETTINGS SECTION

        //* Set this to true if you want all units in your map to be
        //* automatically added to StructuredDD. Otherwise you will have to
        //* manually add them with StructuredDD.add(u).
        private constant boolean ADD_ALL_UNITS=true

        //* This is the amount of units that exist in each trigger bucket.
        //* This number should be something between 5 and 30. A good starting
        //* value will be an estimate of your map's average count of units,
        //* divided by 10. When in doubt, just use 20.
        private constant integer BUCKET_SIZE=20

        //* This is how often StructuredDD will search for empty buckets. If
        //* your map has units being created and dying often, a lower value
        //* is better. Anything between 10 and 180 is good. When in doubt,
        //* just use 60.
        private constant real PER_CLEANUP_TIMEOUT=60.

        //>> END SETTINGS SECTION

    endglobals

    //* Our bucket struct which contains a trigger and its associated contents.
    private struct bucket
        integer bucketIndex=0
        trigger trig=CreateTrigger()
        unit array members[BUCKET_SIZE]
    endstruct

    //* Our wrapper struct. We never intend to actually instanciate "a
    //* StructuredDD", we just use this for a pretty, java-like API :3
    struct StructuredDD extends array
        private static boolexpr array conditions
        private static bucket array bucketDB
        private static integer conditionsIndex=-1
        private static integer dbIndex=-1
        private static integer maxDBIndex=-1

        //* This method gets a readily available bucket for a unit to be added.
        //* If the "current" bucket is full, it returns a new one, otherwise
        //* it just returns the current bucket.
        private static method getBucket takes nothing returns integer
            local integer index=0
            local integer returner=-1
            local bucket tempDat
            if thistype.dbIndex!=-1 and thistype.bucketDB[thistype.dbIndex].bucketIndex<BUCKET_SIZE then
                return thistype.dbIndex
            else
                set thistype.maxDBIndex=thistype.maxDBIndex+1
                set thistype.dbIndex=thistype.maxDBIndex
                set tempDat=bucket.create()
                set thistype.bucketDB[.maxDBIndex]=tempDat
                loop
                    exitwhen index>thistype.conditionsIndex
                    call TriggerAddCondition(tempDat.trig,thistype.conditions[index])
                    set index=index+1
                endloop
                return thistype.dbIndex
            endif
            return -1
        endmethod

        //* This method is for adding a handler to the system. Whenever a
        //* handler is added, damage detection will immediately trigger that
        //* handler. There is no way to deallocate a handler, so don't try to
        //* do this dynamically (!) Support for handler deallocation is
        //* feasible (please contact me)
        public static method addHandler takes code func returns nothing
            local bucket tempDat
            local integer index=0
            set thistype.conditionsIndex=thistype.conditionsIndex+1
            set thistype.conditions[thistype.conditionsIndex]=Condition(func)
            loop
                exitwhen index>thistype.maxDBIndex
                set tempDat=thistype.bucketDB[index]
                call TriggerAddCondition(tempDat.trig,thistype.conditions[thistype.conditionsIndex])
                set index=index+1
            endloop
        endmethod

        //* This method adds a unit to the damage detection system. If
        //* ADD_ALL_UNITS is enabled, this method need not be used.
        public static method add takes unit member returns nothing
            local bucket tempDat
            local integer whichBucket=thistype.getBucket()
            set tempDat=thistype.bucketDB[whichBucket]
            set tempDat.bucketIndex=tempDat.bucketIndex+1
            set tempDat.members[tempDat.bucketIndex]=member
            call TriggerRegisterUnitEvent(tempDat.trig,member,EVENT_UNIT_DAMAGED)
        endmethod

        //* This is just an auxillary function for ADD_ALL_UNITS' implementation
        static if ADD_ALL_UNITS then
            private static method autoAddC takes nothing returns boolean
                call thistype.add(GetTriggerUnit())
                return false
            endmethod
        endif

        //* This method is used to check if a given bucket is empty (and thus
        //* can be deallocated) - this is an auxillary reoutine for the
        //* periodic cleanup system.
        private static method bucketIsEmpty takes integer which returns boolean
            local bucket tempDat=thistype.bucketDB[which]
            local integer index=0
            loop
                exitwhen index==BUCKET_SIZE
                //GetUnitTypeId(unit)==0 means that the unit has been removed.
                if GetUnitTypeId(tempDat.members[index])!=0 then
                    return false
                endif
                set index=index+1
            endloop
            return true
        endmethod

        //* This method cleans up any empty buckets periodically by checking
        //* if it has been fully allocated and then checking if all its
        //* members no longer exist.
        private static method perCleanup takes nothing returns nothing
            local integer index=0
            loop
                exitwhen index>thistype.maxDBIndex
                if index!=thistype.dbIndex and thistype.bucketIsEmpty(index) then
                    call DestroyTrigger(thistype.bucketDB[index].trig)
                    call thistype.bucketDB[index].destroy()
                    set thistype.bucketDB[index]=thistype.bucketDB[thistype.maxDBIndex]
                    set thistype.maxDBIndex=thistype.maxDBIndex-1
                    if thistype.maxDBIndex==thistype.dbIndex then
                        set thistype.dbIndex=index
                    endif
                    set index=index-1
                endif
                set index=index+1
            endloop
        endmethod

        //* This is a initialization function necessary for the setup of
        //* StructuredDD.
        private static method onInit takes nothing returns nothing
            local group grp
            local region reg
            local trigger autoAddUnits
            local timer perCleanup
            local unit FoG
            static if ADD_ALL_UNITS then
                //Add starting units
                set grp=CreateGroup()
                call GroupEnumUnitsInRect(grp,bj_mapInitialPlayableArea,null)
                loop
                    set FoG=FirstOfGroup(grp)
                    exitwhen FoG==null
                    call thistype.add(FoG)
                    call GroupRemoveUnit(grp,FoG)
                endloop
                //Add entering units
                set autoAddUnits=CreateTrigger()
                set reg=CreateRegion()
                call RegionAddRect(reg,bj_mapInitialPlayableArea)
                call TriggerRegisterEnterRegion(autoAddUnits,reg,null)
                call TriggerAddCondition(autoAddUnits,Condition(function thistype.autoAddC))
                set autoAddUnits=null
                set reg=null
            endif
            //enable periodic cleanup:
            set perCleanup=CreateTimer()
            call TimerStart(perCleanup,PER_CLEANUP_TIMEOUT,true,function thistype.perCleanup)
            set perCleanup=null
        endmethod
    endstruct
endlibrary
