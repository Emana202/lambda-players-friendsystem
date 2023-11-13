local IsValid = IsValid
local net = net
local pairs = pairs
local table_Count = table.Count
local modulePrefix = "LambdaFriends_"

-- Friend System Convars
local friendsEnabled = CreateLambdaConvar( "lambdaplayers_friend_enabled", 1, true, false, false, "Enables the Lambda Friend system that allows Lambda/Real Players to be friends with each other and treat them as such", 0, 1, { name = "Enable Friend System", type = "Bool", category = "Friend System" } )
local drawHalo = CreateLambdaConvar( "lambdaplayers_friend_drawhalo", 1, true, true, false, "If your Lambda Friends should have a halo drawn around them", 0, 1, { name = "Draw Halos", type = "Bool", category = "Friend System" } )
local friendCount = CreateLambdaConvar( "lambdaplayers_friend_friendcount", 3, true, false, false, "How many friends can a Lambda/Real Player have", 1, 30, { name = "Friend Count", type = "Slider", decimals = 0, category = "Friend System" } )
local friendChance = CreateLambdaConvar( "lambdaplayers_friend_friendchance", 5, true, false, false, "The chance a Lambda Player will spawn as someone's friend", 0, 100, { name = "Friend Chance", type = "Slider", decimals = 0, category = "Friend System" } )
local allowFriendlyfire = CreateLambdaConvar( "lambdaplayers_friend_friendlyfire", 0, true, false, false, "If Lambda Friends shouldn't be able to damage each other", 0, 1, { name = "Friendly Fire", type = "Bool", category = "Friend System" } )
local stickTogether = CreateLambdaConvar( "lambdaplayers_friend_sticktogether", 1, true, false, false, "If Lambda Player Friends should stick together while not busy", 0, 1, { name = "Stick Together", type = "Bool", category = "Friend System" } )
local stickDist = CreateLambdaConvar( "lambdaplayers_friend_stickdistance", 300, true, false, false, "How close should Lambdas stick together with their friend", 100, 1000, { name = "Stick Distance", type = "Slider", decimals = 0, category = "Friend System" } )
local alwaysStickWithPlys = CreateLambdaConvar( "lambdaplayers_friend_alwayssticktogetherwithplayers", 0, true, false, false, "If Lambda Player Friends should always stick together with their Real Player friend", 0, 1, { name = "Always Stick Together With Real Players", type = "Bool", category = "Friend System" } )

-- Game Convars
local ignorePlys = GetConVar( "ai_ignoreplayers" )

-- Permanent Friend Profile Setting
LambdaCreateProfileSetting( "DTextEntry", "l_permafriends", "Friend System", function( pnl, parent )
    pnl:SetZPos( 100 ) -- ZPos is important for the order
    local lbl = LAMBDAPANELS:CreateLabel( "[ Permanent Friend ]\nInput a Lambda Name or a Real Player's name to make them this profile's permanent friend. You can seperate names with commas, for example: Eve,Blizz", parent, TOP )
    lbl:SetSize( 100, 100 )
    lbl:Dock( TOP )
    lbl:SetWrap( true )
    lbl:SetZPos( 99 )
end )

if ( SERVER ) then
    
    local RandomPairs = RandomPairs
    local table_Add = table.Add
    local string_find = string.find
    local string_Explode = string.Explode
    local ipairs = ipairs
    local CurTime = CurTime
    local debugoverlay = debugoverlay
    local string_lower = string.lower
    local player_GetAll = player.GetAll
    local random = math.random
    local VectorRand = VectorRand
    local dev = GetConVar( "developer" )

    util.AddNetworkString( "lambdaplayerfriendsystem_addfriend" )
    util.AddNetworkString( "lambdaplayerfriendsystem_removefriend" )

    -- If Lambda is currently friends with that entity
    -- The second return is whether entity is permament friend
    local function IsLambdaFriendsWith( lambda, ent )
        local isFriend = lambda:GetFriends()[ ent ]
        return isFriend != nil, isFriend == true
    end

    -- If Lambda can become friends with that entity
    local function LambdaCanBeFriendsWith( lambda, ent )
        if !IsValid( ent ) then return false end

        if ent.IsLambdaPlayer then 
            if lambda:GetEnemy() == ent or ent:GetEnemy() == lambda then return false end
            if LambdaTeams and LambdaTeams:AreTeammates( lambda, ent ) == false then return false end
        elseif ent:IsPlayer() then 
            if ignorePlys:GetBool() then return false end
        else
            return false
        end

        local friendTbl = ent.l_friends
        local friendLimit = friendCount:GetInt()
        return ( table_Count( lambda:GetFriends() ) < friendLimit and ( !friendTbl or table_Count( friendTbl ) < friendLimit ) )
    end

    -- Become friends with that entity and add us to friend list
    local function LambdaAddFriend( lambda, ent, isPerma )
        if lambda:IsFriendsWith( ent ) or !lambda:CanBeFriendsWith( ent ) and !isPerma or !friendsEnabled:GetBool() then return end
        ent.l_friends = ( ent.l_friends or {} )
        isPerma = ( isPerma or false )

        lambda.l_friends[ ent ] = isPerma
        ent.l_friends[ lambda ] = isPerma

        net.Start( "lambdaplayerfriendsystem_addfriend" )
            net.WriteEntity( lambda )
            net.WriteEntity( ent )
        net.Broadcast()

        -- Also become friends with entity's friends
        for entFren, _ in pairs( ent.l_friends ) do
            if entFren == lambda or !lambda:CanBeFriendsWith( entFren ) then continue end

            net.Start( "lambdaplayerfriendsystem_addfriend" )
                net.WriteEntity( lambda )
                net.WriteEntity( entFren )
            net.Broadcast()

            lambda.l_friends[ entFren ] = isPerma
            entFren.l_friends[ lambda ] = isPerma
        end
    end

    -- Stop being friends with that entity and remove from the friend list
    local function LambdaRemoveFriend( lambda, ent )
        if !lambda:IsFriendsWith( ent ) then return end

        net.Start( "lambdaplayerfriendsystem_removefriend" )
            net.WriteEntity( lambda )
            net.WriteEntity( ent )
        net.Broadcast()

        lambda.l_friends[ ent ] = nil
        ent.l_friends[ lambda ] = nil
    end

    local function LambdaGetFriends( lambda )
        return lambda.l_friends
    end

    local function OnLambdaInitialized( self, wepent )    
        self.l_friends = {}
        self.l_NearbyFriendCheckT = ( CurTime() + random( 15, 30 ) )

        self.IsFriendsWith = IsLambdaFriendsWith
        self.CanBeFriendsWith = LambdaCanBeFriendsWith
        self.AddFriend = LambdaAddFriend
        self.RemoveFriend = LambdaRemoveFriend
        self.GetFriends = LambdaGetFriends

        -- Randomly set someone as our friend if it passes the chance
        if random( 100 ) <= friendChance:GetInt() then
            self:SimpleTimer( 0.1, function()
                local allPlys = table_Add( GetLambdaPlayers(), player_GetAll() )
                for _, v in RandomPairs( allPlys ) do
                    if v != self and self:CanBeFriendsWith( v ) then
                        self:AddFriend( v )
                        break
                    end
                end
            end, true )
        end
    end

    -- Small helper function
    local function GetPlayerByName( name )
        for _, v in ipairs( player_GetAll() ) do
            if string_lower( v:Nick() ) == string_lower( name ) then return v end
        end
    end

    -- Set up profile's permanent friends
    local function HandleProfiles( self, info )
        local permafriendsstring = self.l_permafriends
        if !permafriendsstring then return end

        if string_find( permafriendsstring, "," ) then
            for _, name in ipairs( string_Explode( ",", permafriendsstring ) ) do
                local ply = GetPlayerByName( name )
                if IsValid( ply ) then 
                    self:AddFriend( ply, true )
                else
                    ply = GetLambdaPlayerByName( name )
                    if IsValid( ply ) then self:AddFriend( ply, true ) end
                end
            end
        else
            local ply = GetPlayerByName( permafriendsstring )
            if IsValid( ply ) then 
                self:AddFriend( ply, true )
            else
                ply = GetLambdaPlayerByName( permafriendsstring )
                if IsValid( ply ) then self:AddFriend( ply, true ) end
            end
        end
    end

    local function OnLambdaThink( self, wepent )    
        -- Debug lines that visualizes friends
        if dev:GetBool() then
            for fren, _ in pairs( self:GetFriends() ) do
                debugoverlay.Line( self:WorldSpaceCenter(), fren:WorldSpaceCenter(), 0, self:GetPlyColor():ToColor(), true )
            end
        end

        -- Become friends with nearby players
        if CurTime() > self.l_NearbyFriendCheckT then
            if random( 20 ) == 1 then
                local nearest = self:FindInSphere( nil, 500, function( ent )
                    return ( self:CanBeFriendsWith( ent ) and self:CanSee( ent ) )
                end )
                if #nearest > 0 then self:AddFriend( nearest[ random( #nearest ) ] ) end
            end
            self.l_NearbyFriendCheckT = ( CurTime() + random( 15, 30 ) )
        end
    end

    -- Stick with our friends
    local function OnLambdaBeginMove( self, pos, onNavmesh, options )
        if !stickTogether:GetBool() then return end

        local state = self:GetState()
        if state != "Idle" and state != "FindTarget" then return end

        local fren
        local frens = self:GetFriends()
        if alwaysStickWithPlys:GetBool() then
            for ply, _ in RandomPairs( frens ) do
                if !IsValid( ply ) or !ply:IsPlayer() or !ply:Alive() then continue end
                fren = ply; break 
            end
        end
        if !fren then
            if random( 4 ) != 1 then return end

            for ply, _ in RandomPairs( frens ) do
                if !IsValid( ply ) or !ply:Alive() then continue end
                fren = ply; break 
            end
        end
        if !fren then return end

        local callback = function( lambda )
            if !IsValid( fren ) or !fren:Alive() or !lambda:IsFriendsWith( fren ) then return false end
            local movePos = lambda:GetRandomPosition( fren:GetPos() + fren:GetVelocity(), stickDist:GetInt() )
            local shouldRun = ( !lambda:IsInRange( movePos, 500 ) or fren:IsSprinting() )

            lambda:SetRun( shouldRun )
            if !lambda:IsInRange( fren, 300 ) then lambda:RecomputePath( movePos ) end
        end
        options.callback = callback
        options.cbTime = 1

        local movePos = self:GetRandomPosition( fren:GetPos() + fren:GetVelocity(), stickDist:GetInt() )
        options.run = ( !self:IsInRange( movePos, 500 ) or fren:IsSprinting() )
        
        return movePos, options
    end

    -- Prevent taking damage from our friends
    local function OnLambdaInjured( self, dmginfo )
        local attacker = dmginfo:GetAttacker()
        local isFriends, isPerma = self:IsFriendsWith( attacker )
        if !isFriends then return end

        if !allowFriendlyfire:GetBool() then 
            return true 
        end

        if !isPerma and random( 20 ) == 1 then
            print( self:Nick(), attacker:Nick() )
            self:RemoveFriend( attacker )
        end
    end

    -- Un-friend the person that killed us
    local function OnLambdaKilled( self, dmginfo )
        local attacker = dmginfo:GetAttacker()
        local isFriends, isPerma = self:IsFriendsWith( attacker )

        if isFriends and !isPerma and random( 4 ) == 1 then 
            print( self:Nick(), attacker:Nick() )
            self:RemoveFriend( attacker ) 
        end
    end

    -- Defend our friends if we see the attacker or become friends with attacker that's enemy is the same as ours
    local function OnLambdaOtherInjured( self, victim, dmginfo, tookDamage )
        if !tookDamage then return end

        local attacker = dmginfo:GetAttacker()
        if attacker == self or !LambdaIsValid( attacker ) then return end

        local ene = self:GetEnemy()
        if !LambdaIsValid( ene ) then
            if self:IsFriendsWith( victim ) and self:CanTarget( attacker ) and ( self:IsInRange( attacker, 400 ) or self:CanSee( attacker ) ) then
                self:AttackTarget( attacker ) 
            elseif self:IsFriendsWith( attacker ) and self:CanTarget( victim ) and ( self:IsInRange( victim, 400 ) or self:CanSee( victim ) ) then 
                self:AttackTarget( victim ) 
            end
        elseif victim == ene and victim != attacker and random( 30 ) == 1 then
            self:AddFriend( attacker )
        end
    end

    local function OnLambdaOtherKilled( self, victim, dmginfo )
        if !self:IsFriendsWith( victim ) or !self:Alive() or self:InCombat() then return end

        local attacker = dmginfo:GetAttacker()
        if attacker == self or !IsValid( attacker ) or !self:CanTarget( attacker ) or random( 3 ) == 1 then return end

        self:AttackTarget( attacker )
    end

    -- Don't target our friends
    local function OnLambdaCanTarget( self, target ) -- Do not attack friends
        if self:IsFriendsWith( target ) then return true end
    end

    -- Become friends with someone who just healed us
    local function OnLambdaPickupEnt( self, ent )
        if !_LAMBDAPLAYERSItemPickupFunctions[ ent:GetClass() ] or ( CurTime() - ent:GetCreationTime() ) > 5 or random( 20 ) != 1 then return end

        local creator = ent:GetCreator()
        if creator == self or !IsValid( creator ) then return end

        self:AddFriend( creator )
    end

    -- Remove ourselves from our friends's friend list
    local function OnLambdaRemoved( self )
        for fren, _ in pairs( self:GetFriends() ) do self:RemoveFriend( fren ) end
    end

    hook.Add( "LambdaOnProfileApplied", modulePrefix .. "HandleProfiles", HandleProfiles )
    hook.Add( "LambdaOnInitialize", modulePrefix .. "OnLambdaInitialized", OnLambdaInitialized )
    hook.Add( "LambdaOnThink", modulePrefix .. "OnLambdaThink", OnLambdaThink )
    hook.Add( "LambdaOnBeginMove", modulePrefix .. "OnLambdaBeginMove", OnLambdaBeginMove )
    hook.Add( "LambdaOnInjured", modulePrefix .. "OnLambdaInjured", OnLambdaInjured )
    hook.Add( "LambdaOnKilled", modulePrefix .. "OnLambdaKilled", OnLambdaKilled )
    hook.Add( "LambdaOnOtherInjured", modulePrefix .. "OnLambdaOtherInjured", OnLambdaOtherInjured )
    hook.Add( "LambdaOnOtherKilled", modulePrefix .. "OnLambdaOtherKilled", OnLambdaOtherKilled )
    hook.Add( "LambdaCanTarget", modulePrefix .. "OnLambdaCanTarget", OnLambdaCanTarget )
    hook.Add( "LambdaOnPickupEnt", modulePrefix .. "OnLambdaPickupEnt", OnLambdaPickupEnt )
    hook.Add( "LambdaOnRemove", modulePrefix .. "OnLambdaRemoved", OnLambdaRemoved )

    -- Players don't take damage from Lambda friends
    local function OnEntityTakeDamage( ent, dmginfo )
        if !ent:IsPlayer() then return end
        local attacker = dmginfo:GetAttacker()
        if attacker.IsLambdaPlayer and attacker:IsFriendsWith( ent ) and !allowFriendlyfire:GetBool() then return true end
    end

    hook.Add( "EntityTakeDamage", modulePrefix .. "OnEntityTakeDamage", OnEntityTakeDamage )

end

if ( CLIENT ) then

    local LocalPlayer = LocalPlayer
    local AddHalo = halo.Add
    local clientcolor = Color( 255, 145, 0 )
    local tracetable = {}
    local Trace = util.TraceLine
    local DrawText = draw.DrawText
    local CreateFont = surface.CreateFont
    local table_IsEmpty = table.IsEmpty
    local uiscale = GetConVar( "lambdaplayers_uiscale" )
    local ScrW = ScrW
    local ScrH = ScrH

    -- Draw the outlines
    local function OnPreDrawHalos()
        local friends = LocalPlayer().l_friends
        if !friends or !drawHalo:GetBool() then return end

        for k, _ in pairs( friends ) do
            if !LambdaIsValid( k ) or !k:IsBeingDrawn() then continue end
            AddHalo( { k }, k:GetDisplayColor(), 3, 3, 1, true, false )
        end
    end

    -- Display Friend tag and who the Lambda is friends with
    local function OnHUDPaint()
        local ply = LocalPlayer()
        local friends = ply.l_friends
        
        if friends then
            tracetable.start = ply:EyePos()
            tracetable.filter = ply

            for v, _ in pairs( friends ) do
                if !LambdaIsValid( v ) or !v:IsBeingDrawn() then continue end
                tracetable.endpos = v:WorldSpaceCenter()

                local result = Trace( tracetable )
                if result.Entity != v and result.Fraction != 1 then continue end

                local toScreen = ( v:GetPos() + v:OBBCenter() * 2.5 ):ToScreen()
                if !toScreen.visible then continue end

                DrawText( "Friend", "lambdaplayers_displayname", toScreen.x, toScreen.y, v:GetDisplayColor(), TEXT_ALIGN_CENTER )
            end
        end

        local traceent = ply:GetEyeTrace().Entity
        if LambdaIsValid( traceent ) and traceent.IsLambdaPlayer then
            if LambdaRunHook( "LambdaShowNameDisplay", traceent ) == false then return end

            local lambdaFriends = traceent.l_friends
            if lambdaFriends and !table_IsEmpty( lambdaFriends ) then
                local buildString = "Friends With: "
                local friendCount = table_Count( lambdaFriends )
                local friendsCounted = 0
                local otherCount = 0
                
                local lambdaFriends = traceent.l_friends
                for k, _ in pairs( lambdaFriends ) do
                    if !IsValid( k ) then lambdaFriends[ k ] = nil continue end

                    friendsCounted = ( friendsCounted + 1 )
                    if friendsCounted > 3 then otherCount = otherCount + 1 continue end

                    buildString = ( buildString .. k:Nick() .. ( friendCount > friendsCounted and ", " or " " ) )
                end
                buildString = ( otherCount > 0 and buildString .. "and " .. ( otherCount ) .. ( otherCount > 1 and " others" or " other" ) or buildString )

                local sw, sh = ScrW(), ScrH()
                local name = traceent:GetLambdaName()
                DrawText( buildString, "lambdaplayers_displayname", ( sw / 2 ), ( sh / 1.77 ) + LambdaScreenScale( 1 + uiscale:GetFloat() ), traceent:GetDisplayColor(), TEXT_ALIGN_CENTER )
            end
        end
    end

    hook.Add( "PreDrawHalos", modulePrefix .. "OnPreDrawHalos", OnPreDrawHalos )
    hook.Add( "HUDPaint", modulePrefix .. "OnHUDPaint", OnHUDPaint )

    net.Receive( "lambdaplayerfriendsystem_addfriend", function() 
        local target = net.ReadEntity()
        if !IsValid( target ) then return end 
        
        local friend = net.ReadEntity()
        if !IsValid( friend ) then return end

        target.l_friends = ( target.l_friends or {} )
        target.l_friends[ friend ] = true

        friend.l_friends = ( friend.l_friends or {} )
        friend.l_friends[ target ] = true
    end )

    net.Receive( "lambdaplayerfriendsystem_removefriend", function() 
        local target = net.ReadEntity()
        local friend = net.ReadEntity()

        if IsValid( target ) and target.l_friends then
            target.l_friends[ friend ] = nil
        end
        if IsValid( friend ) and friend.l_friends then
            friend.l_friends[ target ] = nil
        end
    end )
end