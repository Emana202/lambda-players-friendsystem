local IsValid = IsValid
local net = net
local pairs = pairs
local table_Count = table.Count
local modulePrefix = "LambdaFriends_"

-- Friend System Convars
local friendsEnabled    = CreateLambdaConvar( "lambdaplayers_friend_enabled", 1, true, false, false, "Enables the friend system that will allow Lambda Players to be friends with each other or with players and treat them as such", 0, 1, { name = "Enable Friend System", type = "Bool", category = "Friend System" } )
local drawHalo          = CreateLambdaConvar( "lambdaplayers_friend_drawhalo", 1, true, true, false, "If friends should have a halo around them", 0, 1, { name = "Draw Halos", type = "Bool", category = "Friend System" } )
local friendCount       = CreateLambdaConvar( "lambdaplayers_friend_friendcount", 3, true, false, false, "How many friends a Lambda/Real Player can have", 1, 30, { name = "Friend Count", type = "Slider", decimals = 0, category = "Friend System" } )
local friendChance      = CreateLambdaConvar( "lambdaplayers_friend_friendchance", 5, true, false, false, "The chance a Lambda Player will spawn as someone's friend", 1, 100, { name = "Friend Chance", type = "Slider", decimals = 0, category = "Friend System" } )

-- Game Convars
local ignorePlys        = GetConVar( "ai_ignoreplayers" )

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
    local function IsLambdaFriendsWith( lambda, ent )
        return ( IsValid( ent ) and IsValid( lambda.l_friends[ ent:GetCreationID() ] ) )
    end

    -- If Lambda can become friends with that entity
    local function LambdaCanBeFriendsWith( lambda, ent )
        if !ent.IsLambdaPlayer and ( !ent:IsPlayer() or ignorePlys:GetBool() ) then return false end
        local friendTbl = ent.l_friends
        local friendLimit = friendCount:GetInt()
        return ( table_Count( lambda.l_friends ) < friendLimit and ( !friendTbl or table_Count( friendTbl ) < friendLimit ) )
    end

    -- Become friends with that entity and add us to friend list
    local function LambdaAddFriend( lambda, ent, forceAdd )
        if lambda:IsFriendsWith( ent ) or !lambda:CanBeFriendsWith( ent ) and !forceAdd or !friendsEnabled:GetBool() then return end
        ent.l_friends = ent.l_friends or {}

        local selfID = lambda:GetCreationID()
        local entID = ent:GetCreationID()

        lambda.l_friends[ entID ] = ent
        ent.l_friends[ selfID ] = lambda

        net.Start( "lambdaplayerfriendsystem_addfriend" )
            net.WriteEntity( lambda )
            net.WriteEntity( ent )
            net.WriteUInt( entID, 32 )
            net.WriteUInt( selfID, 32 )
        net.Broadcast()

        -- Also become friends with entity's friends
        for ID, entFriend in pairs( ent.l_friends ) do
            if entFriend == lambda or !lambda:CanBeFriendsWith( entFriend ) then continue end
            entID = entFriend:GetCreationID()

            net.Start( "lambdaplayerfriendsystem_addfriend" )
                net.WriteEntity( lambda )
                net.WriteEntity( entFriend )
                net.WriteUInt( entID, 32 )
                net.WriteUInt( selfID, 32 )
            net.Broadcast()

            lambda.l_friends[ entID ] = entFriend
            entFriend.l_friends[ selfID ] = lambda
        end
    end

    -- Stop being friends with that entity and remove from the friend list
    local function LambdaRemoveFriend( lambda, ent )
        if !lambda:IsFriendsWith( ent ) then return end

        local selfID = lambda:GetCreationID()
        local entID = ent:GetCreationID()

        net.Start( "lambdaplayerfriendsystem_removefriend" )
            net.WriteEntity( lambda )
            net.WriteEntity( ent )
            net.WriteUInt( selfID, 32 )
            net.WriteUInt( entID, 32 )
        net.Broadcast()

        lambda.l_friends[ entID ] = nil
        ent.l_friends[ selfID ] = LoadNewsList
    end

    local function OnLambdaInitialized( self, wepent )    
        self.l_friends = {}
        self.l_NearbyFriendCheckT = ( CurTime() + 15 )
    
        self.IsFriendsWith = IsLambdaFriendsWith
        self.CanBeFriendsWith = LambdaCanBeFriendsWith
        self.AddFriend = LambdaAddFriend
        self.RemoveFriend = LambdaRemoveFriend

        -- Randomly set someone as our friend if it passes the chance
        if random( 0, 100 ) < friendChance:GetInt() then
            local allPlys = table_Add( GetLambdaPlayers(), player_GetAll() )
            for _, v in RandomPairs( allPlys ) do
                if v != self and self:CanBeFriendsWith( v ) then
                    self:AddFriend( v )
                    break
                end
            end
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
            for _, v in pairs( self.l_friends ) do
                debugoverlay.Line( self:WorldSpaceCenter(), v:WorldSpaceCenter(), 0, self:GetPlyColor():ToColor(), true )
            end
        end

        -- Become friends with nearby players
        if CurTime() > self.l_NearbyFriendCheckT then
            if random( 1, 20 ) == 1 then
                local nearest = self:GetClosestEntity( nil, 200, function( ent ) return self:CanBeFriendsWith( ent ) end )
                if IsValid( nearest ) then self:AddFriend( nearest ) end
            end

            self.l_NearbyFriendCheckT = ( CurTime() + random( 15, 30 ) )
        end
    end

    -- Stick with our friends
    local function OnLambdaBeginMove( self, pos, onNavmesh )
        if random( 1, 4 ) != 1 then return end

        local state = self:GetState()
        if state != "Idle" and state != "FindTarget" then return end

        local rndFriend; for _, v in RandomPairs( self.l_friends ) do rndFriend = v break end
        if !IsValid( rndFriend ) then return end

        local friendPos = ( rndFriend:GetPos() + VectorRand( -500, 500 ) )
        local nearArea = ( onNavmesh and navmesh.GetNearestNavArea( friendPos ) )
        local movePos = ( IsValid( nearArea ) and nearArea:GetClosestPointOnArea( friendPos ) or friendPos )

        self:RecomputePath( friendPos )
    end
    
    -- Prevent taking damage from our friends
    local function OnLambdaInjured( self, dmginfo )
        if self:IsFriendsWith( dmginfo:GetAttacker() ) then return true end
    end

    -- Defend our friends if we see the attacker or become friends with attacker that's enemy is the same as ours
    local function OnLambdaOtherInjured( self, victim, dmginfo, tookDamage )
        if !tookDamage then return end

        local attacker = dmginfo:GetAttacker()
        if attacker == self or !LambdaIsValid( attacker ) then return end

        local ene = self:GetEnemy()
        if !LambdaIsValid( self:GetEnemy() ) then
            if self:IsFriendsWith( victim ) and self:CanTarget( attacker ) and self:CanSee( attacker ) then
                self:AttackTarget( attacker ) 
            elseif self:IsFriendsWith( attacker ) and self:CanTarget( victim ) and self:CanSee( victim ) then 
                self:AttackTarget( victim ) 
            end
        elseif victim == ene and random( 1, 10 ) == 1 then
            self:AddFriend( attacker )
        end
    end

    -- Don't target our friends
    local function OnLambdaCanTarget( self, target ) -- Do not attack friends
        if self:IsFriendsWith( target ) then return true end
    end
    
    local healEntities = {
        [ "item_healthkit" ] = true,
        [ "item_healthvial" ] = true,
        [ "item_battery" ] = true,
        [ "sent_ball" ] = true
    }

    -- Become friends with someone who just healed us
    local function OnLambdaPickupEnt( self, ent )
        if random( 1, 20 ) != 1 or !healEntities[ ent:GetClass() ] or ( CurTime() - ent:GetCreationTime() ) >= 5 then return end

        local creator = ent:GetCreator()
        if creator == self or !IsValid( creator ) then return end

        self:AddFriend( creator )
    end

    -- Remove ourselves from our friends's friend list
    local function OnLambdaRemoved( self )
        for _, friend in pairs( self.l_friends ) do
            self:RemoveFriend( friend )
        end
    end
    
    hook.Add( "LambdaOnProfileApplied", modulePrefix .. "HandleProfiles", HandleProfiles )
    hook.Add( "LambdaOnInitialize", modulePrefix .. "OnLambdaInitialized", OnLambdaInitialized )
    hook.Add( "LambdaOnThink", modulePrefix .. "OnLambdaThink", OnLambdaThink )
    hook.Add( "LambdaOnBeginMove", modulePrefix .. "OnLambdaBeginMove", OnLambdaBeginMove )
    hook.Add( "LambdaOnInjured", modulePrefix .. "OnLambdaInjured", OnLambdaInjured )
    hook.Add( "LambdaOnOtherInjured", modulePrefix .. "OnLambdaOtherInjured", OnLambdaOtherInjured )
    hook.Add( "LambdaCanTarget", modulePrefix .. "OnLambdaCanTarget", OnLambdaCanTarget )
    hook.Add( "LambdaOnPickupEnt", modulePrefix .. "OnLambdaPickupEnt", OnLambdaPickupEnt )
    hook.Add( "LambdaOnRemove", modulePrefix .. "OnLambdaRemoved", OnLambdaRemoved )

    -- Players don't take damage from Lambda friends
    local function OnEntityTakeDamage( ent, dmginfo )
        if !ent:IsPlayer() then return end
        local attacker = dmginfo:GetAttacker()
        if attacker.IsLambdaPlayer and attacker:IsFriendsWith( ent ) then return true end
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
    local uiscale = GetConVar( "lambdaplayers_uiscale" )

    local function UpdateFont()
        CreateFont( "lambdaplayers_friendfont", {
            font = "ChatFont",
            size = LambdaScreenScale( 7 + uiscale:GetFloat() ),
            weight = 0,
            shadow = true
        })
    end
    UpdateFont()
    cvars.AddChangeCallback( "lambdaplayers_uiscale", UpdateFont, "lambdafriendsystemfonts" )

    -- Draw the outlines
    local function OnPreDrawHalos()
        local friends = LocalPlayer().l_friends
        if !friends or !drawHalo:GetBool() then return end

        for _, v in pairs( friends ) do
            if !LambdaIsValid( v ) or !v:IsBeingDrawn() then continue end
            AddHalo( { v }, v:GetDisplayColor(), 3, 3, 1, true, false )
        end
    end

    -- Display Friend tag and who the Lambda is friends with
    local function OnHUDPaint()
        local ply = LocalPlayer()
        local friends = ply.l_friends
        
        if friends then
            tracetable.start = ply:EyePos()
            tracetable.filter = ply

            for _, v in pairs( friends ) do
                if !LambdaIsValid( v ) or !v:IsBeingDrawn() then continue end
                tracetable.endpos = v:WorldSpaceCenter()

                local result = Trace( tracetable )
                if result.Entity != v and result.Fraction != 1 then continue end

                local toScreen = ( v:GetPos() + v:OBBCenter() * 2.5 ):ToScreen()
                if !toScreen.visible then continue end

                DrawText( "Friend", "lambdaplayers_friendfont", toScreen.x, toScreen.y, v:GetDisplayColor(), TEXT_ALIGN_CENTER )
            end
        end

        local traceent = ply:GetEyeTrace().Entity
        if LambdaIsValid( traceent ) and traceent.IsLambdaPlayer then
            local lambdaFriends = traceent.l_friends
            if lambdaFriends and !table_IsEmpty( lambdaFriends ) then
                local buildString = "Friends With: "
                local friendCount = table_Count( lambdaFriends )
                local friendsCounted = 0
                local otherCount = 0
                
                local lambdaFriends = traceent.l_friends
                for k, v in pairs( lambdaFriends ) do
                    if !IsValid( v ) then lambdaFriends[ k ] = nil continue end

                    friendsCounted = ( friendsCounted + 1 )
                    if friendsCounted > 3 then otherCount = otherCount + 1 continue end

                    buildString = ( buildString .. v:Nick() .. ( friendCount > friendsCounted and ", " or " " ) )
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
        target.l_friends[ net.ReadUInt( 32 ) ] = friend

        friend.l_friends = ( friend.l_friends or {} )
        friend.l_friends[ net.ReadUInt( 32 ) ] = target
    end )

    net.Receive( "lambdaplayerfriendsystem_removefriend", function() 
        local target = net.ReadEntity()
        local friend = net.ReadEntity()
        local targetID = net.ReadUInt( 32 )
        local friendID = net.ReadUInt( 32 )

        if IsValid( target ) and target.l_friends then
            target.l_friends[ friendID ] = nil
        end
        if IsValid( friend ) and friend.l_friends then
            friend.l_friends[ targetID ] = nil
        end
    end )
end