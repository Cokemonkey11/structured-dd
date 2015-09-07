
// This script requires that StructuredDD.ADD_ALL_UNITS is enabled.
scope Test initializer init
    private function h takes nothing returns nothing
        local string attackerName = GetUnitName(GetEventDamageSource())
        local string damage       = R2S(GetEventDamage())
        local string struckName   = GetUnitName(GetTriggerUnit())

        call DisplayTextToPlayer(GetLocalPlayer(), 0., 0., attackerName + " dealt " + damage + " to " + struckName)
    endfunction

    private function init takes nothing returns nothing
        call FogMaskEnable(false)
        call FogEnable(false)

        call StructuredDD.addHandler(function h)
    endfunction
endscope
