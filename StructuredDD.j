
// StructuredDD is a damage detection system for handling the generic "unit is
// damaged" event response. The API follows:
//
//
//      StructuredDD.addHandler(function f)
//
//          * Registers function f as a callback function, which will occur
//            whenever a unit, which has been added to the system, is damaged.
//          * In the context of a handler function f, use standard jass natives
//            like:
//                - GetTriggerUnit()       - returns the damaged unit
//                - GetEventDamageSource() - returns the attacking unit
//                - GetEventDamage()       - returns how much damage was dealt
//
//
//      StructuredDD.add(unit u)
//
//          * Manually adds a unit the damage detection system, so that all
//            damage handlers are called when it receives damage.
//          * Note that if `ADD_ALL_UNITS` is enabled, there is no need to
//            manually add a unit.
//
//
library StructuredDD
    globals

        ///////////////////////////////////////////////////////////////////////
        //                            CONFIGURATION
        ///////////////////////////////////////////////////////////////////////

        // When enabled, all units in the map will be added to the damage
        // detection system.
        private constant boolean ADD_ALL_UNITS = true

        // The bucket size determines how many units should be added to each
        // damage detection bucket. Many variables impact the performance
        // for this process. If in doubt, use a number between 10 and 30.
        private constant integer BUCKET_SIZE = 20

        // Controls the period, in seconds, for the vacuum interval. Higher
        // values will have higher success rate, but may become more costly. If
        // in doubt, use a number between 30. and 180.
        private constant real PER_CLEANUP_TIMEOUT = 60.

        ///////////////////////////////////////////////////////////////////////
        //                          END CONFIGURATION
        ///////////////////////////////////////////////////////////////////////

    endglobals


    // A bucket represents a fragment of the units that are managed by the
    // damage detection engine. Essentially, each bucket has a trigger and a
    // set of units. When all the units in the bucket die, the trigger is
    // destroed. This allows more granular recycling of triggers, rather than
    // rebuilding one huge trigger synchronously, as traditional methods do.
    private struct bucket
        integer bucketIndex = 0
        trigger trig = CreateTrigger()
        unit array members[BUCKET_SIZE]
    endstruct


    // The StructuredDD struct is just a wrapper, which provides the API with
    // "dot" syntax.
    struct StructuredDD extends array

        // The conditions array manages *all* conditions in the context of the
        // damage detector. When a new bucket is instantiated, all conditions
        // are added to it. When a condition is added, all existing bucket's
        // triggers receive the condition.
        private static boolexpr array conditions

        private static bucket   array bucketDB

        private static integer conditionsIndex = -1
        private static integer dbIndex         = -1
        private static integer maxDBIndex      = -1

        // This auxilliary method is used for getting the next available
        // bucket. Since buckets get units added to them one at a time, but
        // have capacity for many, this method arbitrates when to use the last
        // bucket and when to build a new one.
        private static method getBucket takes nothing returns integer
            local integer index    =  0
            local integer returner = -1
            local bucket tempDat

            if thistype.dbIndex != -1 and thistype.bucketDB[thistype.dbIndex].bucketIndex < BUCKET_SIZE then

                // A non-full bucket context is already known, so use it.
                return thistype.dbIndex
            else

                // This is either the first bucket requested, or the last
                // bucket used is now full - instantiate a new one.
                set thistype.maxDBIndex = thistype.maxDBIndex + 1
                set thistype.dbIndex = thistype.maxDBIndex
                set tempDat = bucket.create()
                set thistype.bucketDB[.maxDBIndex] = tempDat

                // Add all known handlers to the new bucket.
                loop
                    exitwhen index > thistype.conditionsIndex

                    call TriggerAddCondition(tempDat.trig, thistype.conditions[index])

                    set index = index + 1
                endloop

                return thistype.dbIndex
            endif

            // This line never executes, but some versions of JassHelper will
            // flag an error without it.
            return -1
        endmethod

        // Adds a new "handler" function to the list of functions that are
        // executed when a unit is damaged. Adding a handler will immediately
        // enable it in all buckets. Removing handlers is not supported, so
        // this should not be used dynamically.
        public static method addHandler takes code func returns nothing
            local bucket tempDat
            local integer index = 0

            set thistype.conditionsIndex = thistype.conditionsIndex + 1
            set thistype.conditions[thistype.conditionsIndex] = Condition(func)

            // Immediately add this new handler to all buckets.
            loop
                exitwhen index > thistype.maxDBIndex

                set tempDat = thistype.bucketDB[index]
                call TriggerAddCondition(tempDat.trig, thistype.conditions[thistype.conditionsIndex])

                set index = index + 1
            endloop
        endmethod

        // Adds a unit to the damage detection system using some bucket. When
        // the unit dies or is removed, the bucket will eventually empty and
        // get recycled. If you enable the `ADD_ALL_UNITS` configuration
        // variable, then there is no need to use this method.
        public static method add takes unit member returns nothing
            local bucket tempDat
            local integer whichBucket = thistype.getBucket()

            set tempDat = thistype.bucketDB[whichBucket]
            set tempDat.bucketIndex = tempDat.bucketIndex+1
            set tempDat.members[tempDat.bucketIndex] = member

            // When a unit is added to a bucket, the event for it is
            // immediately enabled.
            call TriggerRegisterUnitEvent(tempDat.trig,member, EVENT_UNIT_DAMAGED)
        endmethod

        // This auxilliary method is part of the implementation for
        // `ADD_ALL_UNITS`. It adds a unit to the damage detection context,
        // when triggered below.
        static if ADD_ALL_UNITS then
            private static method autoAddC takes nothing returns boolean
                call thistype.add(GetTriggerUnit())

                return false
            endmethod
        endif

        // This auxilliary method is used to check if a bucket is empty, and
        // is used to arbitrate when a bucket (and its associated trigger) can
        // be deallocated. This occurs as part of the periodic cleanup system
        // and can be disabled.
        private static method bucketIsEmpty takes integer which returns boolean
            local bucket tempDat = thistype.bucketDB[which]
            local integer index = 0

            loop
                exitwhen index == BUCKET_SIZE

                // If a unit is removed, it's `TypeId` will return 0, at least
                // for some period before its pointer leaves cache or is
                // reused.
                if GetUnitTypeId(tempDat.members[index]) != 0 then
                    return false
                endif

                set index = index + 1
            endloop

            return true
        endmethod

        // This method is called periodically and checks the buckets contents,
        // and recycles them if they are empty. A better implementation would
        // cycle through one bucket a time per iteration, rather than
        // synchronously iterating through all buckets.
        private static method perCleanup takes nothing returns nothing
            local integer index = 0

            loop
                exitwhen index > thistype.maxDBIndex

                if index != thistype.dbIndex and thistype.bucketIsEmpty(index) then

                    // The bucket at this index is empty, so begin
                    // deallocating.
                    call DestroyTrigger(thistype.bucketDB[index].trig)
                    call thistype.bucketDB[index].destroy()

                    set thistype.bucketDB[index] = thistype.bucketDB[thistype.maxDBIndex]
                    set thistype.maxDBIndex = thistype.maxDBIndex - 1

                    if thistype.maxDBIndex == thistype.dbIndex then
                        set thistype.dbIndex = index
                    endif

                    set index = index - 1
                endif

                set index = index + 1
            endloop
        endmethod

        // This struct initialization method is necessary for setting up the
        // damage detection system.
        private static method onInit takes nothing returns nothing
            local group   grp
            local region  reg
            local trigger autoAddUnits
            local timer   perCleanup
            local unit    FoG

            // If the `ADD_ALL_UNITS` configuration is enabled, turns on a
            // trigger which allocates all new units to a bucket. Also checks
            // units that are on the map at initialization.
            static if ADD_ALL_UNITS then

                // Add pre-placed units.
                set grp = CreateGroup()
                call GroupEnumUnitsInRect(grp, bj_mapInitialPlayableArea, null)

                loop
                    set FoG = FirstOfGroup(grp)
                    exitwhen FoG == null

                    call thistype.add(FoG)

                    call GroupRemoveUnit(grp,FoG)
                endloop

                // Add units that enter the map using a trigger.
                set autoAddUnits = CreateTrigger()
                set reg = CreateRegion()

                call RegionAddRect(reg, bj_mapInitialPlayableArea)
                call TriggerRegisterEnterRegion(autoAddUnits, reg, null)
                call TriggerAddCondition(autoAddUnits, Condition(function thistype.autoAddC))

                set autoAddUnits = null
                set reg = null
            endif

            // Enable the periodic cleanup module, which vacuums each bucket
            // periodically.
            set perCleanup = CreateTimer()
            call TimerStart(perCleanup, PER_CLEANUP_TIMEOUT, true, function thistype.perCleanup)

            set perCleanup = null
        endmethod
    endstruct
endlibrary
