--***************************************************************
--
-- gearboxMogliMotor
-- 
-- version 2.200 by mogli (biedens)
--
--***************************************************************

local gearboxMogliVersion=2.200

-- allow modders to include this source file together with mogliBase.lua in their mods
if gearboxMogliMotor == nil or gearboxMogliMotor.version == nil or gearboxMogliMotor.version < gearboxMogliVersion then

--**********************************************************************************************************	
-- gearboxMogliMotor
--**********************************************************************************************************	

gearboxMogliMotor = {}
gearboxMogliMotor_mt = Class(gearboxMogliMotor)

setmetatable( gearboxMogliMotor, { __index = function (table, key) return VehicleMotor[key] end } )

--**********************************************************************************************************	
-- gearboxMogliMotor:new
--**********************************************************************************************************	
function gearboxMogliMotor:new( vehicle, motor )

	if Vehicle.mrLoadFinished ~= nil then
		print("gearboxMogli: init of motor with moreRealistic. self.mrIsMrVehicle = "..tostring(vehicle.mrIsMrVehicle))
	end

	local interpolFunction = linearInterpolator1
	local interpolDegree   = 2
	
	local self = {}

	setmetatable(self, gearboxMogliMotor_mt)

	self.vehicle          = vehicle
	self.original         = motor 	
	self.torqueCurve      = AnimCurve:new( interpolFunction, interpolDegree )
	
	if gearboxMogli.powerFuelCurve == nil then
		gearboxMogli.powerFuelCurve = AnimCurve:new( interpolFunction, interpolDegree )
		gearboxMogli.powerFuelCurve:addKeyframe( {v=0.010, time=0.0} )
		gearboxMogli.powerFuelCurve:addKeyframe( {v=0.125, time=0.02} )
		gearboxMogli.powerFuelCurve:addKeyframe( {v=0.240, time=0.06} )
		gearboxMogli.powerFuelCurve:addKeyframe( {v=0.360, time=0.12} )
		gearboxMogli.powerFuelCurve:addKeyframe( {v=0.500, time=0.2} )
		gearboxMogli.powerFuelCurve:addKeyframe( {v=0.800, time=0.4} )
		gearboxMogli.powerFuelCurve:addKeyframe( {v=0.952, time=0.6} )
		gearboxMogli.powerFuelCurve:addKeyframe( {v=0.986, time=0.7} )
		gearboxMogli.powerFuelCurve:addKeyframe( {v=1.000, time=0.8} )
		gearboxMogli.powerFuelCurve:addKeyframe( {v=0.978, time=0.9} )
		gearboxMogli.powerFuelCurve:addKeyframe( {v=0.909, time=1.0} )
	end
	
	if vehicle.mrGbMS.Engine.maxTorque > 0 then
		for _,k in pairs(vehicle.mrGbMS.Engine.torqueValues) do
			self.torqueCurve:addKeyframe( k )	
		end
		self.torqueCurve:addKeyframe( {v=0, time = self.vehicle.mrGbMS.CurMaxRpm + 0.01 } )
		
		if vehicle.mrGbMS.Engine.ecoTorqueValues ~= nil then
			self.ecoTorqueCurve = AnimCurve:new( interpolFunction, interpolDegree )
			for _,k in pairs(vehicle.mrGbMS.Engine.ecoTorqueValues) do
				self.ecoTorqueCurve:addKeyframe( k )	
			end
			self.ecoTorqueCurve:addKeyframe( {v=0, time = self.vehicle.mrGbMS.CurMaxRpm + 0.01 } )
		end
	
		self.maxTorqueRpm   = vehicle.mrGbMS.Engine.maxTorqueRpm
		self.maxMotorTorque = vehicle.mrGbMS.Engine.maxTorque
	else
		local idleTorque    = motor.torqueCurve:get(vehicle.mrGbMS.OrigMinRpm) --/ self.vehicle.mrGbMS.TransmissionEfficiency
		self.torqueCurve:addKeyframe( {v=0.1*idleTorque, time=0} )
		self.torqueCurve:addKeyframe( {v=0.9*idleTorque, time=vehicle.mrGbMS.CurMinRpm} )
		local vMax  = 0
		local tMax  = vehicle.mrGbMS.OrigMaxRpm
		local tvMax = 0
		local vvMax = 0
		for _,k in pairs(motor.torqueCurve.keyframes) do
			if k.time > vehicle.mrGbMS.CurMinRpm and ( k.v > 0.000001 or k.time < 0.999999 ) then 
				local kv = k.v --/ self.vehicle.mrGbMS.TransmissionEfficiency
				local kt = math.min( k.time, vehicle.mrGbMS.CurMaxRpm - 1 )
				
				if vvMax < k.v then
					vvMax = k.v
					tvMax = k.time
				end
				
				vMax = kv
				tMax = kt
				
				self.torqueCurve:addKeyframe( {v=kv, time=kt} )				
			end
		end		
		
		if vMax > 0 and tMax <= vehicle.mrGbMS.CurMaxRpm - 1 then
			local r = Utils.clamp( vehicle.mrGbMS.CurMaxRpm - tMax, 1, gearboxMogli.rpmRatedMinus )
			self.torqueCurve:addKeyframe( {v=0.9*vMax, time=tMax + 0.25*r} )
			self.torqueCurve:addKeyframe( {v=0.5*vMax, time=tMax + 0.50*r} )
			self.torqueCurve:addKeyframe( {v=0.1*vMax, time=tMax + 0.75*r} )
			self.torqueCurve:addKeyframe( {v=0, time=tMax + r} )
			tMax = tMax + r
		end
		self.torqueCurve:addKeyframe( {v=0, time = self.vehicle.mrGbMS.CurMaxRpm + 0.01 } )
		
		self.maxTorqueRpm   = tvMax	
		self.maxMotorTorque = self.torqueCurve:getMaximum()
	end

	self.fuelCurve = AnimCurve:new( interpolFunction, interpolDegree )
	if vehicle.mrGbMS.Engine.fuelUsageValues == nil then		
		self.fuelCurve:addKeyframe( { v = 0.96 * vehicle.mrGbMS.GlobalFuelUsageRatio, time = self.vehicle.mrGbMS.CurMinRpm } )
		self.fuelCurve:addKeyframe( { v = 0.94 * vehicle.mrGbMS.GlobalFuelUsageRatio, time = self.vehicle.mrGbMS.IdleRpm } )
		self.fuelCurve:addKeyframe( { v = 0.91 * vehicle.mrGbMS.GlobalFuelUsageRatio, time = 0.8*self.vehicle.mrGbMS.IdleRpm+0.2*self.vehicle.mrGbMS.RatedRpm } )		
		self.fuelCurve:addKeyframe( { v = 0.90 * vehicle.mrGbMS.GlobalFuelUsageRatio, time = 0.6*self.vehicle.mrGbMS.IdleRpm+0.4*self.vehicle.mrGbMS.RatedRpm } )		
		self.fuelCurve:addKeyframe( { v = 0.92 * vehicle.mrGbMS.GlobalFuelUsageRatio, time = 0.3*self.vehicle.mrGbMS.IdleRpm+0.7*self.vehicle.mrGbMS.RatedRpm } )		
		self.fuelCurve:addKeyframe( { v = 1.00 * vehicle.mrGbMS.GlobalFuelUsageRatio, time = self.vehicle.mrGbMS.RatedRpm } )		
		self.fuelCurve:addKeyframe( { v = 1.25 * vehicle.mrGbMS.GlobalFuelUsageRatio, time = 0.5*self.vehicle.mrGbMS.RatedRpm+0.5*self.vehicle.mrGbMS.CurMaxRpm } )		
		self.fuelCurve:addKeyframe( { v = 2.00 * vehicle.mrGbMS.GlobalFuelUsageRatio, time = self.vehicle.mrGbMS.CurMaxRpm } )		
		self.fuelCurve:addKeyframe( { v = 10 * vehicle.mrGbMS.GlobalFuelUsageRatio, time = vehicle.mrGbMS.CurMaxRpm + 1 } )		
	else
		for _,k in pairs(vehicle.mrGbMS.Engine.fuelUsageValues) do
			if k.time < self.vehicle.mrGbMS.CurMaxRpm + 1 then
				self.fuelCurve:addKeyframe( k )	
			end
		end
		self.fuelCurve:addKeyframe( { v = 2100, time = vehicle.mrGbMS.CurMaxRpm + 1 } )		
	end
	
--local minTargetRpm = math.max( vehicle.mrGbMS.MinTargetRpm, self.vehicle.mrGbMS.IdleRpm+1 )
	local minTargetRpm = self.vehicle.mrGbMS.IdleRpm+1
	
	self.rpmPowerCurve  = AnimCurve:new( interpolFunction, interpolDegree )	
	self.maxPower       = minTargetRpm * self.torqueCurve:get( minTargetRpm ) 	
	self.maxPowerRpm    = self.vehicle.mrGbMS.RatedRpm 
	self.maxMaxPowerRpm = self.vehicle.mrGbMS.RatedRpm
	self.rpmPowerCurve:addKeyframe( {v=minTargetRpm-1, time=0} )				
	self.rpmPowerCurve:addKeyframe( {v=minTargetRpm,   time=gearboxMogli.powerCurveFactor*self.maxPower} )		

	local lastP = self.maxPower 
	local lastR = self.maxPowerRpm

	for _,k in pairs(self.torqueCurve.keyframes) do			
		local p = k.v*k.time
		if     p      >  self.maxPower then
			self.maxPower       = p
			self.maxPowerRpm    = k.time
			self.maxMaxPowerRpm = k.time
			self.rpmPowerCurve:addKeyframe( {v=k.time, time=gearboxMogli.powerCurveFactor*self.maxPower} )		
		elseif  p     >= gearboxMogli.maxPowerLimit * self.maxPower then
			self.maxMaxPowerRpm = k.time
		elseif  lastP >= gearboxMogli.maxPowerLimit * self.maxPower 
		    and lastP >  p + gearboxMogli.eps then
			self.maxMaxPowerRpm = lastR + ( k.time - lastR ) * ( lastP - gearboxMogli.maxPowerLimit * self.maxPower ) / ( lastP - p )
		end
		lastP = p
		lastR = k.time
	end
	if gearboxMogli.powerCurveFactor < 1 then
		local f = 0.5 * ( 1 + gearboxMogli.powerCurveFactor )
		self.rpmPowerCurve:addKeyframe( {v=self.maxMaxPowerRpm, time=f*self.maxPower} )			
		self.rpmPowerCurve:addKeyframe( {v=self.maxPowerRpm,    time=self.maxPower} )			
	end
	
	if self.ecoTorqueCurve ~= nil then
		self.maxEcoPower   = minTargetRpm * self.ecoTorqueCurve:get( minTargetRpm ) 		
		self.ecoPowerCurve = AnimCurve:new( interpolFunction, interpolDegree )
		self.ecoPowerCurve:addKeyframe( {v=minTargetRpm-1, time=0} )				
		self.ecoPowerCurve:addKeyframe( {v=minTargetRpm,   time=gearboxMogli.powerCurveFactor*self.maxEcoPower} )		
		for _,k in pairs(self.ecoTorqueCurve.keyframes) do			
			local p = k.v*k.time
			if self.maxEcoPower < p then
				self.maxEcoPower  = p
				self.ecoPowerCurve:addKeyframe( {v=k.time, time=gearboxMogli.powerCurveFactor*self.maxEcoPower} )		
			end
		end
		if gearboxMogli.powerCurveFactor < 1 then
			local f = 0.5 * ( 1 + gearboxMogli.powerCurveFactor )
			self.ecoPowerCurve:addKeyframe( {v=self.maxMaxPowerRpm, time=f*self.maxEcoPower} )		
			self.ecoPowerCurve:addKeyframe( {v=self.maxPowerRpm,    time=self.maxEcoPower} )		
		end
	end
	
	if vehicle.mrGbMS.HydrostaticEfficiency ~= nil then
		self.hydroEff = AnimCurve:new( linearInterpolator1 )
		local ktime, kv
		for _,k in pairs(vehicle.mrGbMS.HydrostaticEfficiency) do
			if ktime == nil then
				self.hydroEff:addKeyframe( { time = k.time-2*gearboxMogli.eps, v = 0 } )
				self.hydroEff:addKeyframe( { time = k.time-gearboxMogli.eps, v = k.v } )
			end
			ktime = k.time
			kv    = k.v
			self.hydroEff:addKeyframe( k )
		end
		self.hydroEff:addKeyframe( { time = ktime+gearboxMogli.eps, v = kv } )
		self.hydroEff:addKeyframe( { time = ktime+2*gearboxMogli.eps, v = 0 } )
	end
	
	gearboxMogliMotor.copyRuntimeValues( motor, self )
	
	self.nonClampedMotorRpm      = 0
	self.clutchRpm               = 0
	self.lastMotorRpm            = 0
	self.lastRealMotorRpm        = 0
	self.equalizedMotorRpm       = 0
	
	self.minRpm                  = vehicle.mrGbMS.OrigMinRpm
	self.maxRpm                  = vehicle.mrGbMS.OrigMaxRpm	
	self.minRequiredRpm          = self.vehicle.mrGbMS.IdleRpm
	self.maxClutchTorque         = motor.maxClutchTorque
	self.brakeForce              = motor.brakeForce
	self.lastBrakeForce          = 0
	self.gear                    = 0
	self.gearRatio               = 0
	self.forwardGearRatios       = motor.forwardGearRatio
	self.backwardGearRatios      = motor.backwardGearRatio
	self.minForwardGearRatio     = motor.minForwardGearRatio
	self.maxForwardGearRatio     = motor.maxForwardGearRatio
	self.minBackwardGearRatio    = motor.minBackwardGearRatio
	self.maxBackwardGearRatio    = motor.maxBackwardGearRatio
	self.rpmFadeOutRange         = motor.rpmFadeOutRange
	self.usedTransTorque         = 0
	self.noTransTorque           = 0
	self.motorLoadP              = 0
	self.targetRpm               = self.vehicle.mrGbMS.IdleRpm
	self.requiredWheelTorque     = 0

	self.maxForwardSpeed         = motor.maxForwardSpeed 
	self.maxBackwardSpeed        = motor.maxBackwardSpeed 
	if vehicle.mrGbMS.MaxForwardSpeed  ~= nil then
		self.maxForwardSpeed       = vehicle.mrGbMS.MaxForwardSpeed / 3.6 
	end
	if vehicle.mrGbMS.MaxBackwardSpeed ~= nil then
		self.maxBackwardSpeed      = vehicle.mrGbMS.MaxBackwardSpeed / 3.6
	end
	self.ptoMotorRpmRatio        = motor.ptoMotorRpmRatio

	self.maxTorque               = motor.maxTorque
	self.lowBrakeForceScale      = motor.lowBrakeForceScale
	self.lowBrakeForceSpeedLimit = 0.01 -- motor.lowBrakeForceSpeedLimit
		
	self.maxPossibleRpm          = self.vehicle.mrGbMS.RatedRpm
	self.wheelSpeedRpm           = 0
	self.noTransmission          = true
	self.noTorque                = true
	self.ptoOn                   = false
	self.clutchPercent           = 0
	self.minThrottle             = 0.3
	self.idleThrottle            = self.vehicle.mrGbMS.IdleEnrichment
	self.prevMotorRpm            = 0 --motor.lastMotorRpm
	self.prevNonClampedMotorRpm  = 0 --motor.nonClampedMotorRpm
	self.nonClampedMotorRpmS     = 0 --motor.nonClampedMotorRpm
	self.deltaRpm                = 0
	self.transmissionInputRpm    = 0
	self.motorLoad               = 0
	self.usedMotorTorque         = 0
	self.fuelMotorTorque         = 0
	self.lastMotorTorque         = 0
	self.lastTransTorque         = 0
	self.ptoToolTorque           = 0
	self.ptoMotorRpm             = self.vehicle.mrGbMS.IdleRpm
	self.ptoToolRpm              = 0
	self.ptoMotorTorque          = 0
	self.lastMissingTorque       = 0
	self.lastCurMaxRpm           = self.vehicle.mrGbMS.CurMaxRpm
	self.lastAbsDeltaRpm         = 0
	self.limitMaxRpm             = true
	self.motorLoadS              = 0
	self.requestedPower          = 0
	self.maxRpmIncrease          = 0
	self.tickDt                  = 0
	self.absWheelSpeedRpm        = 0
	self.absWheelSpeedRpmS       = 0
	self.autoClutchPercent       = 0
	self.lastThrottle            = 0
	self.lastClutchClosedTime    = 0
	self.brakeNeutralTimer       = 0
	self.hydrostaticFactor       = 1
	self.rpmIncFactor            = self.vehicle.mrGbMS.RpmIncFactor	
	self.lastBrakeForce          = 0
	self.ratedFuelRatio          = self.fuelCurve:get( self.vehicle.mrGbMS.RatedRpm )
	self.transmissionEfficiency  = 0	
	self.ratioFactorG            = 1
	self.ratioFactorR            = nil
	
	self.brakeForceRatio         = 0
	if vehicle.mrGbMS.BrakeForceRatio > 0 then
		local r0 = math.max( self.maxMaxPowerRpm, vehicle.mrGbMS.RatedRpm )
		if r0 > vehicle.mrGbMS.IdleRpm + gearboxMogli.eps then
			self.brakeForceRatio     = vehicle.mrGbMS.BrakeForceRatio / ( r0 - vehicle.mrGbMS.IdleRpm )
		end
	end
	
	self.boost                   = nil
	self:chooseTorqueCurve( true )
	
	if vehicle.mrIsMrVehicle then
		for n,v in pairs( motor ) do
			if      type( n ) == "string" 
					and string.sub( n, 1, 2 ) == "mr" 
					and ( type( v ) == "number" or type( v ) == "boolean" or type( v ) == "string" ) then
				self[n] = v
			end
		end
		self.rotInertiaFx             = motor.rotInertiaFx
		self.mrLastAxleTorque         = 0
		self.mrLastEngineOutputTorque = 0
		self.mrLastDummyGearRatio     = 0
		self.mrMaxTorque              = 0
	end
	
	return self
end

--**********************************************************************************************************	
-- gearboxMogliMotor.chooseTorqueCurve
--**********************************************************************************************************	
function gearboxMogliMotor:chooseTorqueCurve( eco )
	local lastBoost = self.boost
	if eco and self.ecoTorqueCurve ~= nil then
		self.boost              = false
		self.currentTorqueCurve = self.ecoTorqueCurve
		self.currentPowerCurve  = self.ecoPowerCurve
		self.currentMaxPower    = self.maxEcoPower 
	else
		self.boost              = ( self.ecoTorqueCurve ~= nil )
		self.currentTorqueCurve = self.torqueCurve
		self.currentPowerCurve  = self.rpmPowerCurve
		self.currentMaxPower    = self.maxPower 
	end
	
	self.maxMotorTorque = self.currentTorqueCurve:getMaximum()
	self.maxRatedTorque = self.currentTorqueCurve:get( self.vehicle.mrGbMS.RatedRpm )
	
	if lastBoost == nil or self.boost ~= lastBoost then
		self.debugTorqueGraph             = nil
		self.debugPowerGraph              = nil
		self.debugEffectiveTorqueGraph    = nil
		self.debugEffectivePowerGraph     = nil
		self.debugEffectiveGearRatioGraph = nil
		self.debugEffectiveRpmGraph       = nil
	end
end

--**********************************************************************************************************	
-- gearboxMogliMotor.getTorqueCurve
--**********************************************************************************************************	
function gearboxMogliMotor:getTorqueCurve()
	return self.currentTorqueCurve
end

--**********************************************************************************************************	
-- gearboxMogliMotor.copyRuntimeValues
--**********************************************************************************************************	
function gearboxMogliMotor.copyRuntimeValues( motorFrom, motorTo )

	if motorFrom.vehicle ~= nil and not ( motorTo.vehicle.isMotorStarted ) then
		motorTo.nonClampedMotorRpm    = 0
		motorTo.clutchRpm             = 0
		motorTo.lastMotorRpm          = 0
		motorTo.lastRealMotorRpm      = 0
		motorTo.equalizedMotorRpm     = 0
	else
		motorTo.nonClampedMotorRpm    = Utils.getNoNil( motorFrom.nonClampedMotorRpm, 0 )
		motorTo.clutchRpm             = Utils.getNoNil( motorFrom.clutchRpm        , motorTo.nonClampedMotorRpm )   
		motorTo.lastMotorRpm          = Utils.getNoNil( motorFrom.lastMotorRpm     , motorTo.nonClampedMotorRpm )  
		motorTo.lastRealMotorRpm      = Utils.getNoNil( motorFrom.lastRealMotorRpm , motorTo.nonClampedMotorRpm )      
		motorTo.equalizedMotorRpm     = Utils.getNoNil( motorFrom.equalizedMotorRpm, motorTo.nonClampedMotorRpm )
	end
	motorTo.lastPtoRpm              = motorFrom.lastPtoRpm
	motorTo.gear                    = motorFrom.gear               
	motorTo.gearRatio               = motorFrom.gearRatio          
	motorTo.rpmLimit                = motorFrom.rpmLimit 
	motorTo.speedLimit              = motorFrom.speedLimit
	motorTo.minSpeed                = motorFrom.minSpeed

	motorTo.rotInertia              = motorFrom.rotInertia 
	motorTo.dampingRate             = motorFrom.dampingRate

end

--**********************************************************************************************************	
-- gearboxMogliMotor:getHydroEff
--**********************************************************************************************************	
function gearboxMogliMotor:getHydroEff( h )
	if self.hydroEff == nil then
		return 1
	elseif  self.vehicle.mrGbMS.ReverseActive
			and self.vehicle.mrGbMS.HydrostaticMin < 0 then
		h = -h
	end
	if self.vehicle.mrGbMS.HydrostaticMin <= h and h <= self.vehicle.mrGbMS.HydrostaticMax then
		return self.hydroEff:get( h )
	end
	print("FS17_GearboxAddon: Error! hydrostaticFactor out of range: "..tostring(h))
	return 0
end

--**********************************************************************************************************	
-- gearboxMogliMotor:getLimitedGearRatio
--**********************************************************************************************************	
function gearboxMogliMotor:getLimitedGearRatio( r, withSign, noWarning )
	if type( r ) ~= "number" then
		print("FS17_GearboxAddon: Error! gearRatio is not a number: "..tostring(r))
		gearboxMogli.printCallStack( self.vehicle )
		if self.vehicle.mrGbMS.ReverseActive then
			return -gearboxMogli.maxGearRatio
		else
			return  gearboxMogli.maxGearRatio
		end
	end
	
	local a = r
	if withSign and r < 0 then
		a = -r
	end		
	
	if a < gearboxMogli.minGearRatio then
		if not ( noWarning ) then
			print("FS17_GearboxAddon: Error! gearRatio is too small: "..tostring(r))
			gearboxMogli.printCallStack( self.vehicle )
		end
		if withSign and r < 0 then
			return -gearboxMogli.minGearRatio
		else
			return  gearboxMogli.minGearRatio
		end
	end
	
	if a > gearboxMogli.maxGearRatio then
		if not ( noWarning ) then
			print("FS17_GearboxAddon: Error! gearRatio is too big: "..tostring(r))
			gearboxMogli.printCallStack( self.vehicle )
		end
		if withSign and r < 0 then
			return -gearboxMogli.maxGearRatio
		else
			return  gearboxMogli.maxGearRatio
		end
	end

	return r
end

--**********************************************************************************************************	
-- gearboxMogliMotor:getGearRatio
--**********************************************************************************************************	
function gearboxMogliMotor:getGearRatio( withWarning )
	return self:getLimitedGearRatio( self.gearRatio, true, not ( withWarning ) )
end

--**********************************************************************************************************	
-- gearboxMogliMotor:getMogliGearRatio
--**********************************************************************************************************	
function gearboxMogliMotor:getMogliGearRatio()
	return gearboxMogli.gearSpeedToRatio( self.vehicle, self.vehicle.mrGbMS.CurrentGearSpeed )
end

--**********************************************************************************************************	
-- gearboxMogliMotor:getGearRatioFactor
--**********************************************************************************************************	
function gearboxMogliMotor:getGearRatioFactor()
	return self.clutchRpm / self:getMotorRpm()
end

--**********************************************************************************************************	
-- gearboxMogliMotor:getSpeedLimit
--**********************************************************************************************************	
function gearboxMogliMotor:getSpeedLimit( )
	return self.currentSpeedLimit
end

--**********************************************************************************************************	
-- gearboxMogliMotor:updateSpeedLimit
--**********************************************************************************************************	
function gearboxMogliMotor:updateSpeedLimit( dt )
	self.currentSpeedLimit = math.huge
	
	local speedLimit = self.vehicle:getSpeedLimit(true)
	
	if not ( self.vehicle.steeringEnabled ) then
		speedLimit = math.min( speedLimit, self.speedLimit )
	end
	
	if      self.vehicle.tempomatMogliV22 ~= nil 
			and self.vehicle.tempomatMogliV22.keepSpeedLimit ~= nil then
		speedLimit = math.min( speedLimit, self.vehicle.tempomatMogliV22.keepSpeedLimit )
	end
	
	speedLimit = speedLimit * gearboxMogli.kmhTOms

	if     self.vehicle.mrGbMS.SpeedLimiter 
			or self.vehicle.cruiseControl.state == Drivable.CRUISECONTROL_STATE_ACTIVE then

		local cruiseSpeed = math.min( speedLimit, self.vehicle.cruiseControl.speed * gearboxMogli.kmhTOms )
		if dt == nil then
			dt = self.tickDt
		end
		
		if self.speedLimitS == nil then 
			self.speedLimitS = math.abs( self.vehicle.lastSpeedReal*1000 )
		end
		-- limit speed limiter change to given km/h per second
		local limitMax   =  0.001 * gearboxMogli.kmhTOms * self.vehicle:mrGbMGetAccelerateToLimit() * dt
		local decToLimit = self.vehicle:mrGbMGetDecelerateToLimit()
		---- avoid to much brake force => limit to 7 km/h/s if difference below 2.77778 km/h difference
		if self.speedLimitS - 1 < cruiseSpeed and cruiseSpeed < self.speedLimitS and decToLimit > 7 then
			decToLimit     = 7
		end
		local limitMin   = -0.001 * gearboxMogli.kmhTOms * decToLimit * dt
		self.speedLimitS = self.speedLimitS + Utils.clamp( math.min( cruiseSpeed, self.maxForwardSpeed ) - self.speedLimitS, limitMin, limitMax )
		if cruiseSpeed < self.maxForwardSpeed or self.speedLimitS < 0.97 * self.maxForwardSpeed then
			cruiseSpeed = self.speedLimitS
		end
		
		if speedLimit > cruiseSpeed then
			speedLimit = cruiseSpeed
		end
	else
		self.speedLimitS = math.min( speedLimit, math.abs( self.vehicle.lastSpeedReal*1000 ) )
	end

	if self.vehicle.mrGbML.hydroTargetSpeed ~= nil and speedLimit > self.vehicle.mrGbML.hydroTargetSpeed then
		speedLimit = self.vehicle.mrGbML.hydroTargetSpeed
	end
	
	if self.vehicle.mrGbMS.MaxSpeedLimiter then
		local maxSpeed = self.maxForwardSpeed
		
		if self.vehicle.mrGbMS.ReverseActive then
			maxSpeed = self.maxBackwardSpeed
		end		
		
		if speedLimit > maxSpeed then
			speedLimit = maxSpeed
		end
	end
						
	self.currentSpeedLimit = speedLimit 
	
	return speedLimit + gearboxMogli.extraSpeedLimitMs
end

--**********************************************************************************************************	
-- gearboxMogliMotor:getCurMaxRpm
--**********************************************************************************************************	
function gearboxMogliMotor:getCurMaxRpm( forGetTorque )

	curMaxRpm = gearboxMogli.huge
						
	if self.ratioFactorR ~= nil and self.ratioFactorR > 1e-6 then 		
		if forGetTorque or not ( self.vehicle.mrGbMS.Hydrostatic ) then
			curMaxRpm = ( self.maxPossibleRpm + gearboxMogli.speedLimitRpmDiff ) / self.ratioFactorR
		end
	
		local speedLimit   = gearboxMogli.huge
		
		if self.ptoSpeedLimit ~= nil then
			speedLimit = self.ptoSpeedLimit
		end
		
		if forGetTorque or self.limitMaxRpm then
			speedLimit = math.min( speedLimit, self:getSpeedLimit() )
		elseif self.ptoOn then
			speedLimit = math.min( speedLimit, self:getSpeedLimit() + gearboxMogli.speedLimitBrake )
		end
		
		if speedLimit < gearboxMogli.huge then
			speedLimit = speedLimit + gearboxMogli.extraSpeedLimitMs
			curMaxRpm  = Utils.clamp( speedLimit * gearboxMogli.factor30pi * self:getMogliGearRatio() * self.ratioFactorG, 1, curMaxRpm )
		end
		
		if self.rpmLimit ~= nil and self.rpmLimit < curMaxRpm then
			curMaxRpm  = self.rpmLimit
		end
		
		if curMaxRpm < self.vehicle.mrGbMS.CurMinRpm then
			curMaxRpm  = self.vehicle.mrGbMS.CurMinRpm 
		end
		
		speedLimit = self.vehicle:getSpeedLimit(true)
		if speedLimit < gearboxMogli.huge then
			speedLimit = speedLimit * gearboxMogli.kmhTOms
			speedLimit = speedLimit + gearboxMogli.extraSpeedLimitMs
			curMaxRpm  = Utils.clamp( speedLimit * gearboxMogli.factor30pi * self:getMogliGearRatio() * self.ratioFactorG, 1, curMaxRpm )
		end
	end
	
	if forGetTorque then
		if self.ratioFactorR ~= nil then
			curMaxRpm = curMaxRpm * self.ratioFactorR
		else
			curMaxRpm = self.maxPossibleRpm
		end
	else
		self.lastCurMaxRpm = curMaxRpm
	end
	
	return curMaxRpm
end

--**********************************************************************************************************	
-- gearboxMogliMotor:getBestGear
--**********************************************************************************************************	
function gearboxMogliMotor:getBestGear( acceleration, wheelSpeedRpm, accSafeMotorRpm, requiredWheelTorque, requiredMotorRpm )

	local direction = 1
	local gearRatio = self:getMogliGearRatio() * self.ratioFactorG
	
	if self.vehicle.mrGbMS.ReverseActive then
		direction = -1
		gearRatio = -gearRatio
	end
	
	if self.lastDebugGearRatio == nil or math.abs( self.lastDebugGearRatio - gearRatio ) > 1 then
		-- Vehicle.drawDebugRendering !!!
		self.debugEffectiveTorqueGraph    = nil
		self.debugEffectivePowerGraph     = nil
		self.debugEffectiveGearRatioGraph = nil
		self.debugEffectiveRpmGraph       = nil
		self.lastDebugGearRatio           = gearRatio
	end
	
	return direction, gearRatio
end

--**********************************************************************************************************	
-- gearboxMogliMotor:motorStall
--**********************************************************************************************************	
function gearboxMogliMotor:motorStall( warningText1, warningText2 )
	self.vehicle:mrGbMSetNeutralActive(true, false, true)
	if not ( g_currentMission.missionInfo.automaticMotorStartEnabled ) then
		self.vehicle:stopMotor()
	end
end

--**********************************************************************************************************	
-- gearboxMogliMotor:getTorque
--**********************************************************************************************************	
function gearboxMogliMotor:getTorque( acceleration, limitRpm )

	local prevTransTorque = self.lastTransTorque

	self.lastTransTorque         = 0
	self.noTransTorque           = 0
	self.ptoMotorTorque          = 0
	self.lastMissingTorque       = 0
	
	local ptoMotorTorque  = self.ptoMotorTorque	
	local acc             = math.max( self.minThrottle, self.lastThrottle )
	local brakePedal      = 0
	local rpm             = self.lastRealMotorRpm
	local torque          = 0

	local pt = 0	
	if self.ptoToolTorque > 0 then
	  pt = self.ptoToolTorque / self.ptoMotorRpmRatio
	end

	local eco = false
	if      self.ecoTorqueCurve ~= nil
			and ( self.vehicle.mrGbMS.EcoMode
				 or not ( self.ptoToolTorque                     > 0
							 or ( self.vehicle.mrGbMS.IsCombine and self.vehicle:getIsTurnedOn() )
							 or math.abs( self.vehicle.lastSpeedReal ) > self.vehicle.mrGbMS.BoostMinSpeed ) ) then
		eco = true
	end
	self:chooseTorqueCurve( eco )
	
	if self.noTorque then
		torque = 0
	else
		torque = self.currentTorqueCurve:get( rpm ) 
	end
	
	self.lastMotorTorque	= torque
	
	-- no extra combine power in case of MR
	if not ( self.mrIsMrVehicle ) and self.vehicle.mrGbMS.IsCombine then
		local combinePower    = 0
		local combinePowerInc = 0
	
		if self.vehicle.pipeIsUnloading then
			combinePower = combinePower + self.vehicle.mrGbMS.UnloadingPowerConsumption
		end
		
		local sqm = 0
		if self.vehicle:getIsTurnedOn() then
			combinePower  = combinePower    + self.vehicle.mrGbMS.ThreshingPowerConsumption		
			if not ( self.vehicle.isStrawEnabled ) then
				combinePower  = combinePower    + self.vehicle.mrGbMS.ChopperPowerConsumption
			end
		end

		combinePowerInc = combinePowerInc + self.vehicle.mrGbMS.ThreshingPowerConsumptionInc
		if not ( self.vehicle.isStrawEnabled ) then
			combinePowerInc = combinePowerInc + self.vehicle.mrGbMS.ChopperPowerConsumptionInc
		end
		
		if combinePowerInc > 0 then
			combinePower = combinePower + combinePowerInc * gearboxMogli.mrGbMGetCombineLS( self.vehicle )
		end

		pt = pt + ( combinePower / rpm )
	end
	
	if pt > 0 then
		if not ( self.noTransmission 
					or self.noTorque 
					or self.vehicle.mrGbMS.Hydrostatic
					or ( self.vehicle.mrGbMS.TorqueConverter and self.vehicle.mrGbMS.OpenRpm > self.maxPowerRpm - 1 ) ) then
			local mt = self.currentTorqueCurve:get( Utils.clamp( self.lastRealMotorRpm, self.vehicle.mrGbMS.IdleRpm, self.vehicle.mrGbMS.RatedRpm ) ) 
			if mt < pt then
			--print(string.format("Not enough power for PTO: %4.0f Nm < %4.0fNm", mt*1000, pt*1000 ).." @RPM: "..tostring(self.lastRealMotorRpm))
				if self.ptoWarningTimer == nil then
					self.ptoWarningTimer = g_currentMission.time
				end
				if      g_currentMission.time > self.ptoWarningTimer + 10000 then
					self.ptoWarningTimer = nil
					
					gearboxMogliMotor.motorStall( self, string.format("Motor stopped due to missing power for PTO: %4.0f Nm < %4.0fNm", mt*1000, pt*1000 ), 
																								string.format("Not enough power for PTO: %4.0f Nm < %4.0fNm", mt*1000, pt*1000 ) )
				elseif  g_currentMission.time > self.ptoWarningTimer + 2000 then
					self.vehicle:mrGbMSetState( "WarningText", string.format("Not enough power for PTO: %4.0f Nm < %4.0fNm", mt*1000, pt*1000 ))
				end			
			elseif self.ptoWarningTimer ~= nil then
				self.ptoWarningTimer = nil
			end
		else
			self.ptoWarningTimer = nil
		end
		
		local maxPtoTorqueRatio = math.min( 1, self.vehicle.mrGbMS.MaxPtoTorqueRatio + math.abs( self.vehicle.lastSpeedReal*3600 ) * self.vehicle.mrGbMS.MaxPtoTorqueRatioInc )
		
		if     torque < 1e-4 then
			self.ptoMotorTorque = 0
			self.ptoSpeedLimit  = nil
		elseif self.noTransmission 
				or self.noTorque then
			self.ptoMotorTorque = math.min( torque, pt )
			self.ptoSpeedLimit  = nil
		elseif maxPtoTorqueRatio <= 0 then
			self.ptoMotorTorque = 0
		elseif maxPtoTorqueRatio <  1 then
			local m = maxPtoTorqueRatio 
			if self.nonClampedMotorRpm > self.vehicle.mrGbMS.IdleRpm and math.abs( self.vehicle.lastSpeedReal ) > 2.78e-4 then
				m = math.max( m, 1 - self.usedTransTorque / torque )
			end
			self.ptoMotorTorque = math.min( pt, m * torque )
		else
			self.ptoMotorTorque = math.min( pt, torque )
		end
		
		if self.ptoMotorTorque < pt then
			self.lastMissingTorque = self.lastMissingTorque + pt - self.ptoMotorTorque
		end
		torque             = torque - self.ptoMotorTorque
		
--print(string.format("%3d %4d %4d %4d",maxPtoTorqueRatio*100,torque*1000,pt*1000,self.ptoMotorTorque*1000))		
	else
		if self.ptoWarningTimer ~= nil then
			self.ptoWarningTimer = nil
		end
		if self.ptoSpeedLimit   ~= nil then
			self.ptoSpeedLimit   = nil
		end
	end

-- limit RPM
	local limitA = self.vehicle.mrGbMS.CurMaxRpm
	local limitC = self.vehicle.mrGbMS.CurMaxRpm
	
	if self.vehicle.mrGbML.hydroTargetSpeed ~= nil then
		limitA = self.targetRpm * ( 1 + self.vehicle.mrGbMS.HydrostaticLossFxRpmRatio ) + gearboxMogli.ptoRpmThrottleDiff 
	elseif  not self.noTransmission 
			and not self.noTorque
		--and self.vehicle.cruiseControl.state == 0
			and self.vehicle.steeringEnabled then
		if     acc <= gearboxMogli.eps then
			limitA = self.vehicle.mrGbMS.IdleRpm
		elseif acc < self.vehicle.mrGbMS.MaxRpmThrottle
				and ( self.vehicle.mrGbMG.maxRpmThrottleAuto
					 or self.vehicle.mrGbMS.CurrentGearSpeed >= self.vehicle.mrGbMS.AutoMaxGearSpeed - gearboxMogli.eps ) then
			limitA = math.min( limitA, self:getThrottleMaxRpm( acc / self.vehicle.mrGbMS.MaxRpmThrottle ) )
		end
		limitA = math.max( limitA, self.minRequiredRpm )
	end
	
	if not ( self.vehicle.mrGbMS.Hydrostatic ) then
		limitC = math.min( self:getCurMaxRpm( true ), limitA )
	end
		
-- motor brake force
	if self.noTransmission then
		self.lastBrakeForce = 0
		brakeForce          = 0
	else
		local t0 = self.lastMotorTorque
		local r0 = math.max( self.maxMaxPowerRpm, self.vehicle.mrGbMS.RatedRpm )
		local r1 = self.nonClampedMotorRpm
		if     type( self.nonClampedMotorRpm ) ~= "number" then
			r1 = self.vehicle.mrGbMS.IdleRpm
		elseif self.nonClampedMotorRpm > self.vehicle.mrGbMS.CurMaxRpm then
			r1 = self.vehicle.mrGbMS.CurMaxRpm
		end
		if r1 > r0 then
			t0 = math.max( t0, self.torqueCurve:get( r0 ) )
		end
		if     r1 <= self.vehicle.mrGbMS.IdleRpm
				or self.vehicle.mrGbMS.BrakeForceRatio <= 0 then
			brakeForce = 0
		else
			if self.brakeForceRatio > 0 then
				brakeForce = self.brakeForceRatio * ( r1 - self.vehicle.mrGbMS.IdleRpm ) 
			else
				brakeForce = self.vehicle.mrGbMS.BrakeForceRatio
			end
			
			if     self.noTorque 
					or acc <= 0
					or r1  >= limitC + gearboxMogli.brakeForceLimitRpm then
				brakeForce = brakeForce * t0
			else
				local a0 = acc
				if r1 > limitC + gearboxMogli.eps then
					a0 = math.min( a0, ( limitC + gearboxMogli.brakeForceLimitRpm - r1 ) / gearboxMogli.brakeForceLimitRpm )
				end

				if a0 <= 0 then
					brakeForce = brakeForce * t0
				elseif a0 >= 1 then
					brakeForce = 0
				else
					brakeForce = brakeForce * ( t0 - a0 * self.lastMotorTorque )
				end
			end
		end
		self.lastBrakeForce = self.lastBrakeForce + self.vehicle.mrGbML.smoothFast * ( brakeForce - self.lastBrakeForce )
		brakeForce          = self.lastBrakeForce
	end
	
	self.vehicle.mrGbML.rpmLimitInfo = ""
	
	if torque < 0 then
		self.lastMissingTorque = self.lastMissingTorque - torque
		torque                 = 0
	elseif self.noTorque then
		torque                 = 0
	elseif acc <= 0 then
		torque                 = 0
	elseif self.noTransmission then
		torque                 = torque * acc
	else
		local applyLimit = true
		if self.vehicle.mrGbMS.Hydrostatic then
			applyLimit = false
			if self.vehicle.mrGbMS.HydrostaticMin < 0 and self.vehicle.mrGbMS.ReverseActive then
				if self.hydrostaticFactor > -self.vehicle.mrGbMS.HydrostaticMin * 0.98 then
					applyLimit = true
				end
			elseif self.hydrostaticFactor > self.vehicle.mrGbMS.HydrostaticMax * 0.98 then
				applyLimit = true
			end
		end
		
		if applyLimit then
			if not self.limitMaxRpm and self.nonClampedMotorRpm > limitC then
				if self.vehicle.mrGbMG.debugInfo then
					self.vehicle.mrGbML.rpmLimitInfo = string.format( "maxRPM: %4d > %4d => 0 Nm", self.nonClampedMotorRpm, limitC )
				end
				torque = 0
			elseif self.nonClampedMotorRpm > limitA + gearboxMogli.ptoRpmThrottleDiff then
				if self.vehicle.mrGbMG.debugInfo then
					self.vehicle.mrGbML.rpmLimitInfo = string.format( "acc: %4d > %4d => 0 Nm", self.nonClampedMotorRpm, limitA )
				end
				torque = 0
			elseif self.nonClampedMotorRpm > limitA then
				torque = torque * ( limitA + gearboxMogli.ptoRpmThrottleDiff - self.nonClampedMotorRpm ) / gearboxMogli.ptoRpmThrottleDiff		
				if self.vehicle.mrGbMG.debugInfo then
					self.vehicle.mrGbML.rpmLimitInfo = string.format( "acc: %4d > %4d => %4d Nm", self.nonClampedMotorRpm, limitA, torque * 1000 )
				end
			end
			if      self.lastMaxPossibleRpm ~= nil
					and self.nonClampedMotorRpm >= self.minRequiredRpm
					and self.nonClampedMotorRpm >  self.lastMaxPossibleRpm then
			--print(string.format("%4d, %4d, %4d => %4d, %4d, %4d",self.nonClampedMotorRpm,limitA,limitC,self.lastMotorTorque*1000,old*1000,torque*1000))
				if self.nonClampedMotorRpm > self.lastMaxPossibleRpm + gearboxMogli.speedLimitRpmDiff then
					self.lastMotorTorque = self.lastMotorTorque - torque 
					torque               = 0
					if self.vehicle.mrGbMG.debugInfo then
						self.vehicle.mrGbML.rpmLimitInfo = string.format( "possible: %4d > %4d => 0 Nm", self.nonClampedMotorRpm, self.lastMaxPossibleRpm )
					end
				else
					local old = torque
					torque = torque * ( self.lastMaxPossibleRpm + gearboxMogli.speedLimitRpmDiff - self.nonClampedMotorRpm ) / gearboxMogli.speedLimitRpmDiff
					self.lastMotorTorque = self.lastMotorTorque - old + torque
					if self.vehicle.mrGbMG.debugInfo then
						self.vehicle.mrGbML.rpmLimitInfo = string.format( "possible: %4d > %4d => %4d Nm", self.nonClampedMotorRpm, self.lastMaxPossibleRpm, torque * 1000 )
					end
				end
			end
		end
		
		if self.vehicle.mrGbMS.PowerManagement and acc > 0 then
			local p1 = rpm * ( self.lastMotorTorque - self.ptoMotorTorque )
			local p0 = 0
			if self.vehicle.mrGbMS.EcoMode then
				p0 = self.currentMaxPower
			else
				p0 = self.maxPower
			end
			p0 = acc * ( p0 - rpm * self.ptoMotorTorque )
			
			local old = acc
			
			if     p0 <= 0 
					or p1 <= 0 then
				acc = 1
			elseif p0 >= p1 then
				acc = 1
			else
				acc = p0 / p1
			end

			if self.vehicle.mrGbMG.debugInfo then
				self.vehicle.mrGbML.accDebugInfo = string.format( "%3.0f%%, %7.3f %7.3f => %3.0f%%", old*100, p0, p1, acc*100 )
			end
		end		
	end
	
	if     self.noTransmission 
			or self.noTorque then
		self.ptoSpeedLimit = nil
		self.ptoSpeedLimitTimer = nil
	elseif  self.lastMissingTorque > gearboxMogli.ptoSpeedLimitRatio * self.lastMotorTorque 
			and self.vehicle.mrGbMS.PtoSpeedLimit 
			and ( not ( self.vehicle.steeringEnabled ) 
				or  self.vehicle.cruiseControl.state ~= Drivable.CRUISECONTROL_STATE_ACTIVE
				or  self.vehicle.cruiseControl.state ~= Drivable.CRUISECONTROL_STATE_FULL )
			and self.vehicle.lastSpeedReal*1000 > gearboxMogli.ptoSpeedLimitMin then
		if self.ptoSpeedLimit ~= nil then
			self.ptoSpeedLimit = math.max( self.ptoSpeedLimit - self.tickDt * gearboxMogli.ptoSpeedLimitDec, gearboxMogli.ptoSpeedLimitMin )
		elseif self.ptoSpeedLimitTimer == nil then
			self.ptoSpeedLimitTimer = g_currentMission.time + gearboxMogli.ptoSpeedLimitTime
		elseif self.ptoSpeedLimitTimer < g_currentMission.time then
			self.ptoSpeedLimit = math.max( self.vehicle.lastSpeedReal*1000 - gearboxMogli.ptoSpeedLimitIni, gearboxMogli.ptoSpeedLimitMin )
		end
	elseif self.ptoSpeedLimit ~= nil then
		if gearboxMogli.ptoSpeedLimitInc > 0 then
			self.ptoSpeedLimit = self.ptoSpeedLimit + self.tickDt * gearboxMogli.ptoSpeedLimitInc
			if self.ptoSpeedLimit > self.vehicle.lastSpeedReal*1000 + gearboxMogli.ptoSpeedLimitOff then
				self.ptoSpeedLimit = nil
			end
		else
			self.ptoSpeedLimit = nil
		end
		self.ptoSpeedLimitTimer = nil
	end
	
	if limitRpm then
		local maxRpm = self.vehicle.mrGbMS.CurMaxRpm
		local rpmFadeOutRange = self.rpmFadeOutRange * gearboxMogliMotor.getMogliGearRatio( self )
		local fadeStartRpm = maxRpm - rpmFadeOutRange

		if fadeStartRpm < self.nonClampedMotorRpm then
			if maxRpm < self.nonClampedMotorRpm then
				brakePedal = math.min((self.nonClampedMotorRpm - maxRpm)/rpmFadeOutRange, 1)
				torque = 0
			else
				torque = torque*math.max((fadeStartRpm - self.nonClampedMotorRpm)/rpmFadeOutRange, 0)
			end
		end
	end
	
	self.noTransTorque = self.lastMotorTorque * self.idleThrottle

	local lastG = self.ratioFactorG
	self.ratioFactorG = 1
	self.ratioFactorR = 1
	local lastHydroRatio = self.hydrostaticOutputRatio
	self.hydrostaticOutputRatio = nil
	self.transmissionEfficiency = 1
	
	if     torque < 0 then
		self.lastMissingTorque      = self.lastMissingTorque - torque
		self.transmissionEfficiency = 0
		
		if self.hydrostatPressureI ~= nil then
			self.hydrostatPressureI = math.min( self.vehicle.mrGbMS.HydrostaticPressure, self.hydrostatPressureI + self.vehicle.mrGbMS.HydrostaticPressDelta * self.tickDt )
			self.hydrostatPressureO = self.hydrostatPressureI
		end
		
	elseif self.noTransmission then
		self.noTransTorque          = math.max( self.noTransTorque, torque ) * self.vehicle.mrGbMG.idleFuelTorqueRatio
		self.transmissionEfficiency = 0

		if self.hydrostatPressureI ~= nil then
			self.hydrostatPressureI = math.min( self.vehicle.mrGbMS.HydrostaticPressure, self.hydrostatPressureI + self.vehicle.mrGbMS.HydrostaticPressDelta * self.tickDt )
			self.hydrostatPressureO = self.hydrostatPressureI
		end
		
	elseif self.vehicle.mrGbMS.HydrostaticCoupling ~= nil then
		local Mm = torque 		
		local Pi, Po, Mi, Mo, Mf, Mw = 0, 0, 0, 0, 0, 0
		local h  = self.hydrostaticFactor
		
		local hc = self.vehicle.mrGbMS.HydrostaticCoupling
		if self.vehicle.mrGbMS.Gears[self.vehicle.mrGbMS.CurrentGear].hydrostaticCoupling ~= nil then
			hc = self.vehicle.mrGbMS.Gears[self.vehicle.mrGbMS.CurrentGear].hydrostaticCoupling
		end
		
		lastVolP = self.hydrostatVolumePump
		lastVolM = self.hydrostatVolumeMotor
		self.hydrostatVolumePump  = self.vehicle.mrGbMS.HydrostaticVolumePump  * self.vehicle.mrGbMS.HydroInputRPMRatio
		self.hydrostatVolumeMotor = self.vehicle.mrGbMS.HydrostaticVolumeMotor * self.vehicle.mrGbMS.HydroOutputRPMRatio
		
		if self.hydrostatPressureI == nil then
			self.hydrostatPressureI = self.vehicle.mrGbMS.HydrostaticPressure
			lastVolP = self.hydrostatVolumePump
			lastVolM = self.hydrostatVolumeMotor
		end
		
		self.hydrostaticOutputRatio = 1
				
		local loss      = self.vehicle.mrGbMS.HydroPumpMotorEff
		local effFactor = loss^(-2)
		
		if     self.rawTransTorque == nil 
				or lastHydroRatio      == nil
				or lastVolM            <= gearboxMogli.eps then
			self.hydrostatPressureO = 0
		elseif hc == "InputA" or hc == "InputB" then
		elseif prevTransTorque > self.rawTransTorque then
			self.hydrostatPressureO = lastHydroRatio * ( prevTransTorque - self.rawTransTorque ) * loss * 20000 * math.pi / lastVolM
		else
			self.hydrostatPressureO = 0
		end
		
		local Ni, No = rpm, rpm
			
		if     hc == "Output" then	
			if ( self.hydrostatVolumePump + effFactor * self.hydrostatVolumeMotor ) * h < self.hydrostatVolumePump then
				self.hydrostatVolumePump  = math.max( 0, self.hydrostatVolumeMotor * effFactor * h / ( 1 - h ) )
			else
				self.hydrostatVolumeMotor = self.hydrostatVolumePump  * ( 1 - h ) / ( h * effFactor )
			end
			
			Mi = Mm
			Mf = Mm
			Po = self.vehicle.mrGbMS.HydrostaticPressure
			
			Ni = No * self.hydrostatVolumeMotor / self.hydrostatVolumePump
		elseif hc == "InputA" or hc == "InputB" then
		
			local fr = 1	
			if hc == "InputB" and self.vehicle.mrGbMS.CurrentGear ~= 1 then
				fr = self.vehicle.mrGbMS.Gears[1].speed / self.vehicle.mrGbMS.Gears[self.vehicle.mrGbMS.CurrentGear].speed
			end
			
			if self.hydrostaticFactor < 1 then
				loss = 1 / loss			
				h = math.max( (self.hydrostaticFactor-1) * fr / effFactor, -1 )
			else
				h = math.min( (self.hydrostaticFactor-1) * fr * effFactor, 1 )
			end
		
			self.hydrostatVolumePump  = self.hydrostatVolumePump * h
			self.hydrostatVolumeMotor = self.hydrostatVolumeMotor * fr
			Mi = Mm
				
			local Vp = self.hydrostatVolumePump + self.hydrostatVolumeMotor * loss * loss / self.vehicle.mrGbMS.TransmissionEfficiency
			if Vp > gearboxMogli.eps then
				Po = Utils.clamp( Mm * 20000 * math.pi / Vp, 0, self.vehicle.mrGbMS.HydrostaticPressure )
			else
				Po = self.vehicle.mrGbMS.HydrostaticPressure
			end
			No = Ni * ( 1 + self.hydrostatVolumePump / self.hydrostatVolumeMotor )
			
		else
			h = h * effFactor
			if h < 1 then
				self.hydrostatVolumePump  = math.max( 0, self.hydrostatVolumePump  * h )
			else
				self.hydrostatVolumeMotor = self.hydrostatVolumeMotor / h
			end
			Mi = Mm	
			Po = self.vehicle.mrGbMS.HydrostaticPressure
			No = Ni * self.hydrostatVolumePump / self.hydrostatVolumeMotor
		end
		
		if math.abs( self.hydrostatVolumePump ) > gearboxMogli.eps then
			Pi = Utils.clamp( Mi * loss * 20000 * math.pi / math.abs( self.hydrostatVolumePump ), self.hydrostatPressureO, self.vehicle.mrGbMS.HydrostaticPressure )
		else
			Pi = self.vehicle.mrGbMS.HydrostaticPressure
		end
				
		self.hydrostatPressureI = self.hydrostatPressureI + Utils.clamp( self.vehicle.mrGbML.smoothFast * ( Pi - self.hydrostatPressureI ),
																																		-self.vehicle.mrGbMS.HydrostaticPressDelta * self.tickDt,
																																		self.vehicle.mrGbMS.HydrostaticPressDelta * self.tickDt )
	--Pi = self.hydrostatPressureI
		if Po > Pi then
			Po = Pi
		end
		self.hydrostatPressureO = Pi-Po
		Mo = loss * Po * self.hydrostatVolumeMotor / ( 20000 * math.pi )
	
		if hc == "Output" then
			Mw = self.vehicle.mrGbMS.TransmissionEfficiency * ( Mo + Mf )
			if     Mf < gearboxMogli.eps then
				self.hydrostaticOutputRatio = 1
			elseif Mw > gearboxMogli.eps then
				self.hydrostaticOutputRatio = Mo / Mw
			end
			if self.hydrostatVolumePump < 0 then
				self.hydrostaticOutputRatio = -self.hydrostaticOutputRatio
			end
		elseif hc == "InputA" or hc == "InputB" then
			Mi = Po * self.hydrostatVolumePump / ( 20000 * math.pi )
			Mf = Mm - Mi
			--Mw, Mo and t * Mf are identical Mm = Mf + Mi => Mf = Mm - Mi and Mw = t * Mf => Mw = t * ( Mm - Mi )
			if     h < gearboxMogli.eps then
			-- force is going backwards
				Mw = self.vehicle.mrGbMS.TransmissionEfficiency * Mf
			elseif h > gearboxMogli.eps then
			-- the smaller force wins
				Mw = math.min( self.vehicle.mrGbMS.TransmissionEfficiency * Mf, Mo )
			else
			-- hydrostatic drive is locked
				Mw = self.vehicle.mrGbMS.TransmissionEfficiency * Mm
			end
		else 
			Mw = Mo
		end		
	
		if     self.noTransmission 
				or self.noTorque 
				or torque <= 0  then
			self.transmissionEfficiency = 1 / math.max( gearboxMogli.minHydrostaticFactor, self.hydrostaticFactor )
			torque = 0
		elseif Mw < 0 then
			brakeForce = brakeForce - Mw
			self.transmissionEfficiency = 0
		elseif torque > gearboxMogli.eps then
			self.transmissionEfficiency = Mw / torque 
		else
			self.transmissionEfficiency = 1 / math.max( gearboxMogli.minHydrostaticFactor, self.hydrostaticFactor )
			torque = Mw / self.transmissionEfficiency
		end
		
		if self.vehicle.mrGbMG.debugInfo then
			self.vehicle.mrGbML.hydroPumpInfo = string.format("Torque: Mi: %4.0f Mf: %4.0f (%4.0f, %3.0f%%)\nVi: %4.0f Pi: %4.0f Ni: %4.0f\nMo: %4.0f Vo: %4.0f Po: %4.0f No: %4.0f h: %5.3f\n=> %4.0f (%4.0f) => %5.1f%%, %5.1f%%", 
														Mi*1000,
														Mf*1000,
														Mm*1000,
														acc*100,
														self.hydrostatVolumePump,
														Pi,
														Ni,
														Mo*1000,
														self.hydrostatVolumeMotor,
														Po,
														No,
														self.hydrostaticFactor,
														Mw*1000,
														Mw-self.hydrostaticFactor*Mm,
														self.transmissionEfficiency*100,
														self.hydrostaticFactor*self.transmissionEfficiency*100)
		end
	elseif torque > 0 then
					
		local e = self.vehicle.mrGbMG.transmissionEfficiency
		
		if self.vehicle.mrGbMS.Hydrostatic then
			e = self:getHydroEff( self.hydrostaticFactor )
		else
			e = self.vehicle.mrGbMS.TransmissionEfficiency
		end

		if self.noTransmission then
			self.transmissionEfficiency = 0
		elseif self.clutchPercent < gearboxMogli.eps then
			self.transmissionEfficiency = 0
		elseif self.clutchPercent < 1 and self.vehicle.mrGbMS.TorqueConverter then
			self.transmissionEfficiency = self.vehicle.mrGbMS.TorqueConverterEfficiency 
		else
			self.transmissionEfficiency = e
		end
	end
	
	local dLMiddle = false
	local dLFront  = false 
	local dLBack   = false 
	if self.vehicle.mrGbMS.ModifyDifferentials then
		dLMiddle = self.vehicle:mrGbMGetDiffLockMiddle()
		dLFront  = self.vehicle:mrGbMGetDiffLockFront()
		dLBack   = self.vehicle:mrGbMGetDiffLockBack()
	elseif  self.vehicle.driveControl                        ~= nil
			and self.vehicle.driveControl.fourWDandDifferentials ~= nil
			and not ( self.vehicle.driveControl.fourWDandDifferentials.isSurpressed ) then
		dLMiddle = self.vehicle.driveControl.fourWDandDifferentials.fourWheelSet
		dLFront  = self.vehicle.driveControl.fourWDandDifferentials.diffLockFrontSet
		dLBack   = self.vehicle.driveControl.fourWDandDifferentials.diffLockBackSet
	end
	
	if dLMiddle then self.transmissionEfficiency = self.transmissionEfficiency * 0.98 end
	if dLFront  then self.transmissionEfficiency = self.transmissionEfficiency * 0.96 end
	if dLBack   then self.transmissionEfficiency = self.transmissionEfficiency * 0.94 end
		
	torque = torque * math.min( self.transmissionEfficiency, self.vehicle.mrGbMS.TransmissionEfficiency )
	
	if     self.noTransmission
			or not ( self.vehicle.isMotorStarted ) then
		self.ratioFactorR  = nil
		self.lastGearRatio = nil
		self.lastGMax      = nil
		self.lastHydroInvF = nil
		
	elseif self.vehicle.mrGbMS.Hydrostatic then

		local r = self:getMogliGearRatio()
	
		if      self.hydrostaticFactor < gearboxMogli.minHydrostaticFactor then
			if self.vehicle.mrGbMS.ReverseActive then 
				self.lastGearRatio = -gearboxMogli.maxHydroGearRatio
			else
				self.lastGearRatio =  gearboxMogli.maxHydroGearRatio
			end
		end

		if self.vehicle.mrGbMS.HydrostaticCoupling ~= nil then
			if self.transmissionEfficiency > self.vehicle.mrGbMS.TransmissionEfficiency then
				self.ratioFactorG = math.min( self.transmissionEfficiency / self.vehicle.mrGbMS.TransmissionEfficiency, gearboxMogli.maxHydroGearRatio / r )
				self.transmissionEfficiency = self.vehicle.mrGbMS.TransmissionEfficiency 
			else
				self.ratioFactorG = 1
			end
		elseif gearboxMogli.maxHydroGearRatio * self.hydrostaticFactor < r then
			self.ratioFactorG = math.min( self.vehicle.mrGbMS.HydrostaticMaxTorqueFactor, gearboxMogli.maxHydroGearRatio / r )
		else
			self.ratioFactorG = math.min( self.vehicle.mrGbMS.HydrostaticMaxTorqueFactor, 1 / self.hydrostaticFactor )
		end
		
		local g = self:getLimitedGearRatio( r * self.ratioFactorG, false )
		if self.vehicle.mrGbMG.smoothGearRatio and self.lastGearRatio ~= nil then
			local l = self:getLimitedGearRatio( math.abs( self.lastGearRatio ), false )
			if self.lastGearRatio >= gearboxMogli.minGearRatio then
				if g > l + 1 or g < l - 1 then
					local i1 = 1 / g
					local i2 = 1 / l
					g = self:getLimitedGearRatio( 1 / ( i2 + self.vehicle.mrGbML.smoothFast * ( i1 - i2 ) ), false )
				end
			--self.ratioFactorG = g / r
			end
		end
		self.ratioFactorG = g / r
		
		if self.vehicle.mrGbMS.ReverseActive then 
			self.gearRatio = -g
		else
			self.gearRatio =  g
		end
		self.lastGearRatio = self.gearRatio
		
		if self.ratioFactorG * self.hydrostaticFactor * gearboxMogli.maxRatioFactorR < 1 then
		--if acc > 0.5 and self.clutchRpm > self.targetRpm + gearboxMogli.ptoRpmThrottleDiff then
		--	self.ratioFactorR = gearboxMogli.maxRatioFactorR
		--else
				self.ratioFactorR = nil -- gearboxMogli.maxRatioFactorR
		--end
		else
			self.ratioFactorR = 1 / ( self.ratioFactorG * self.hydrostaticFactor )
		end
		
		local f = 1
		
		if      torque < gearboxMogli.eps then
		elseif  self.vehicle.mrGbML.DirectionChangeTime <= g_currentMission.time and g_currentMission.time < self.vehicle.mrGbML.DirectionChangeTime + 2000 then
			f = 1 + ( g_currentMission.time - self.vehicle.mrGbML.DirectionChangeTime ) * 0.001
			if self.ratioFactorR ~= nil then
				f = math.min( f, self.ratioFactorR )
			end
		elseif  self.ratioFactorR == nil  then
			f = gearboxMogli.maxRatioFactorR
		elseif  self.ratioFactorR < 0.999 or self.ratioFactorR > 1.001 then
			f = self.ratioFactorR
		end
		
		if self.lastHydroInvF == nil then
			self.lastHydroInvF = 1
		end
		self.lastHydroInvF = self.lastHydroInvF + self.vehicle.mrGbML.smoothMedium * ( 1 / f - self.lastHydroInvF )
		f = 1 / self.lastHydroInvF
		
		torque = math.min( torque * f, torque * self.vehicle.mrGbMS.HydrostaticMaxTorqueFactor / self.ratioFactorG )
		
	elseif self.autoClutchPercent < 1 and self.vehicle.mrGbMS.TorqueConverter then
		local c = self.clutchRpm / self:getMotorRpm( self.autoClutchPercent )
		
		if c * self.vehicle.mrGbMS.TorqueConverterFactor > 1 then
			self.ratioFactorG = 1 / c
		else
			self.ratioFactorG = self.vehicle.mrGbMS.TorqueConverterFactor
		end
		self.ratioFactorG = lastG + self.vehicle.mrGbML.smoothLittle * ( self.ratioFactorG - lastG )
		-- clutch percentage will be applied additionally => undo ratioFactorG in updateMotorRpm 		
		self.ratioFactorR = 1 / self.ratioFactorG
	end
	
	self.lastTransTorque = torque
	
	return torque, brakePedal, brakeForce
end

--**********************************************************************************************************	
-- gearboxMogliMotor:updateMotorRpm
--**********************************************************************************************************	
function gearboxMogliMotor:updateMotorRpm( dt )
	local vehicle = self.vehicle
	self.tickDt                  = dt
	self.prevNonClampedMotorRpm  = math.min( self.vehicle.mrGbMS.CurMaxRpm, self.nonClampedMotorRpm )
	self.prevMotorRpm            = self.lastRealMotorRpm
	self.prevClutchRpm           = self.clutchRpm
	
	self.nonClampedMotorRpm, self.clutchRpm, self.usedTransTorque = getMotorRotationSpeed(vehicle.motorizedNode)		
	self.nonClampedMotorRpm  = self.nonClampedMotorRpm * gearboxMogli.factor30pi
	self.clutchRpm           = self.clutchRpm          * gearboxMogli.factor30pi
	self.requiredWheelTorque = self.maxMotorTorque*math.abs(self.gearRatio)	
	self.wheelSpeedRpm       = self.vehicle.lastSpeedReal * 1000 * gearboxMogli.factor30pi * self.vehicle.movingDirection	
	self.rawTransTorque      = self.usedTransTorque
	
	if     not ( self.noTransmission ) and math.abs( self.gearRatio ) > gearboxMogli.eps and self.vehicle.mrGbMS.HydrostaticLaunch  then
		self.wheelSpeedRpm = self.clutchRpm / self.gearRatio
	elseif not ( self.noTransmission ) and math.abs( self.gearRatio ) > gearboxMogli.eps and gearboxMogli.trustClutchRpmTimer <= dt then
		local w = self.clutchRpm / self.gearRatio
		if     self.trustClutchRpmTimer == nil 
				or self.trustClutchRpmTimer > g_currentMission.time + 1000 then
			self.trustClutchRpmTimer = g_currentMission.time + 1000
		elseif self.trustClutchRpmTimer < g_currentMission.time then	
			self.wheelSpeedRpm = w
		else
			self.wheelSpeedRpm = self.wheelSpeedRpm + 0.001 * ( self.trustClutchRpmTimer - g_currentMission.time ) * ( w - self.wheelSpeedRpm )
		end
		if self.trustClutchRpmTimer >= g_currentMission.time then
			self.clutchRpm = self.wheelSpeedRpm * self.gearRatio
		end
	elseif self.trustClutchRpmTimer ~= nil then
		self.trustClutchRpmTimer = nil
	end
	
	if self.ratioFactorR ~= nil then	
		self.clutchRpm = self.ratioFactorR * self.clutchRpm          
	else
		if self.vehicle.mrGbMS.Hydrostatic and not self.noTransmission then
			r = self.targetRpm 
		else
			r = self:getThrottleRpm()
		end
		
		if self.prevClutchRpm == nil then
			self.clutchRpm = r
		else
			self.clutchRpm = self.prevClutchRpm + Utils.clamp( r - self.prevClutchRpm, -dt * self.vehicle.mrGbMS.RpmDecFactor, dt * self.vehicle.mrGbMS.RpmIncFactor )
		end
	end
	
	if self.vehicle.isMotorStarted and gearboxMogli.debugGearShift then
		if not ( self.noTransmission ) and self.ratioFactorR ~= nil and self.hydrostaticFactor > gearboxMogli.eps then
			print(string.format("A: %4.2f km/h s: %6.3f w: %6.0f n: %4.0f c: %4.0f g: %6.3f fr: %6.3f fg: %6.3f rc: %6.3f rt: %6.3f h: %6.3f r: %6.3f g: %d", 
													self.vehicle.lastSpeedReal*3600,
													self.wheelSpeedRpm,
													self.wheelSpeedRpm * self:getMogliGearRatio() / self.hydrostaticFactor,
													self.nonClampedMotorRpm,
													self.clutchRpm,
													self.gearRatio,
													self.ratioFactorR,
													self.ratioFactorG,
													self.gearRatio*self.ratioFactorR,
													self:getMogliGearRatio() / self.hydrostaticFactor,
													self.hydrostaticFactor,
													self.ratioFactorR*self.ratioFactorG*self.hydrostaticFactor,
													self.vehicle.mrGbMS.CurrentGear ))
		else
			print(string.format("B: %4.2f km/h s: %6.3f t: %4d c: %4d (%4d) n: %4d (%4d)",
													self.vehicle.lastSpeedReal*3600,
													self.wheelSpeedRpm,
													self:getThrottleRpm(),
													self.clutchRpm, self.prevClutchRpm,
													self.nonClampedMotorRpm, self.prevNonClampedMotorRpm))
		end
	end
	
	if not ( self.vehicle.isMotorStarted ) then
		if self.prevNonClampedMotorRpm == nil then
			self.nonClampedMotorRpm  = 0
		else
			self.nonClampedMotorRpm  = math.max( 0, self.prevNonClampedMotorRpm -dt * self.vehicle.mrGbMS.RpmDecFactor )
		end
		self.lastRealMotorRpm  = self.nonClampedMotorRpm
		self.lastMotorRpm      = self.nonClampedMotorRpm
		self.prevVariableRpm   = nil
		self.motorLoadOverflow = 0
		self.usedTransTorque   = 0
	elseif self.vehicle.motorStartDuration > 0 and g_currentMission.time < self.vehicle.motorStartTime then
		self.motorLoadOverflow = 0
		self.usedTransTorque   = 0
		self.nonClampedMotorRpm= self.vehicle.mrGbMS.IdleRpm * ( 1 - ( self.vehicle.motorStartTime - g_currentMission.time ) / self.vehicle.motorStartDuration )
		self.lastRealMotorRpm  = self.nonClampedMotorRpm
		self.lastMotorRpm      = self.nonClampedMotorRpm
		self.prevVariableRpm   = nil
		self.motorLoadOverflow = 0
		self.usedTransTorque   = 0
	else
		self.nonClampedMotorRpm = self:getMotorRpm()
		
		if self.motorLoadOverflow == nil or self.noTransmission or self.ratioFactorR == nil then
			self.motorLoadOverflow   = 0
		end
		
		self.usedTransTorque = self.usedTransTorque + self.motorLoadOverflow
		if self.usedTransTorque > self.lastTransTorque then
			self.motorLoadOverflow = self.usedTransTorque - self.lastTransTorque
			self.usedTransTorque   = self.lastTransTorque
		else
			self.motorLoadOverflow = 0
		end
	
		if self.noTransmission then
			self.usedTransTorque   = self.noTransTorque
			self.lastRealMotorRpm  = self.lastMotorRpm
		else
			if self.transmissionEfficiency ~= nil and self.transmissionEfficiency > gearboxMogli.eps then
				self.usedTransTorque = self.usedTransTorque / self.transmissionEfficiency
			end
		
			local kmh = math.abs( self.vehicle.lastSpeedReal ) * 3600
			if     kmh < 1 then
				self.usedTransTorque = math.max( self.usedTransTorque, self.noTransTorque )
			elseif kmh < 2 then
				self.usedTransTorque = math.max( self.usedTransTorque, self.noTransTorque * ( kmh - 1 ) )
			end
			
			self.lastRealMotorRpm  = math.max( self.vehicle.mrGbMS.CurMinRpm, math.min( self.nonClampedMotorRpm, self.vehicle.mrGbMS.CurMaxRpm ) )
			
			local m = gearboxMogli.maxManualGearRatio 
			if self.vehicle.mrGbMS.Hydrostatic then	
				m = gearboxMogli.maxHydroGearRatio 
			end		
			if math.abs( self.gearRatio ) >= m - gearboxMogli.eps then
				local minRpmReduced   = Utils.clamp( self.minRequiredRpm * gearboxMogli.rpmReduction, self.vehicle.mrGbMS.CurMinRpm, self.vehicle.mrGbMS.RatedRpm * gearboxMogli.rpmReduction )		
				self.lastRealMotorRpm = math.max( self.lastRealMotorRpm, minRpmReduced )
			end

			local rdf = 0.1 * ( self.vehicle.mrGbMS.RatedRpm - self.vehicle.mrGbMS.IdleRpm )
			local rif = 0.1 * ( self.vehicle.mrGbMS.RatedRpm - self.vehicle.mrGbMS.IdleRpm )
			
			if self.vehicle.mrGbMS.Hydrostatic or self.clutchPercent < 0.9 then
				rdf = self.vehicle.mrGbMS.RpmDecFactor
				rif = self.vehicle.mrGbMS.RpmIncFactor
			elseif self.clutchPercent < 1 then
				rdf = self.vehicle.mrGbMS.RpmDecFactor + ( self.clutchPercent - 0.9 ) * 10 * ( rdf - self.vehicle.mrGbMS.RpmDecFactor )
				rif = self.vehicle.mrGbMS.RpmIncFactor + ( self.clutchPercent - 0.9 ) * 10 * ( rif - self.vehicle.mrGbMS.RpmIncFactor )
			end
			
			self.lastMotorRpm = self.lastMotorRpm + Utils.clamp( ( self.lastRealMotorRpm - self.lastMotorRpm ) * self.vehicle.mrGbML.smoothLittle,
																													 -dt * rdf,
																														dt * rif )
		end
	end
	
	self.lastAbsDeltaRpm = self.lastAbsDeltaRpm + self.vehicle.mrGbML.smoothMedium * ( math.abs( self.prevNonClampedMotorRpm - self.nonClampedMotorRpm ) - self.lastAbsDeltaRpm )	
	self.deltaMotorRpm   = math.floor( self.lastRealMotorRpm - self.nonClampedMotorRpm + 0.5 )
	
	local c = self.clutchPercent
	if not ( self.vehicle.mrGbMS.Hydrostatic or self.vehicle:mrGbMGetAutoClutch() ) then
		c = self.vehicle.mrGbMS.ManualClutch
	end
	local tir = math.max( 0, self.transmissionInputRpm - dt * self.vehicle.mrGbMS.RatedRpm * 0.0001 )
	
	if     c < 0.1 then
		self.transmissionInputRpm = tir
	elseif c > 0.9 then
		self.transmissionInputRpm = self.lastRealMotorRpm
	else
		self.transmissionInputRpm = math.max( self.lastRealMotorRpm, tir )
	end
	
	self.nonClampedMotorRpmS = self.nonClampedMotorRpmS + gearboxMogli.smoothFast * ( self.nonClampedMotorRpm - self.nonClampedMotorRpmS )	
	self.lastPtoRpm          = self.lastRealMotorRpm
	self.equalizedMotorRpm   = self.vehicle:mrGbMGetEqualizedRpm( self.lastMotorRpm )
	
	local utt = self.usedTransTorque
	if self.vehicle.mrIsMrVehicle and gearboxMogli.eps < utt and utt < self.lastTransTorque then
		-- square because MR has rolling resistance etc. => 0%->0%; 50%->25%; 100%->100%
		utt = utt * utt / self.lastTransTorque
	end
	
	if self.noTransmission or self.transmissionEfficiency < gearboxMogli.eps then
		self.usedMotorTorque   = self.usedTransTorque + self.ptoMotorTorque + self.lastMissingTorque
		self.fuelMotorTorque   = utt + self.ptoMotorTorque + self.lastMissingTorque
	else
		self.usedMotorTorque   = math.min( self.usedTransTorque / self.transmissionEfficiency + self.ptoMotorTorque, self.lastMotorTorque ) + self.lastMissingTorque
		self.fuelMotorTorque   = math.min( utt / self.transmissionEfficiency + self.ptoMotorTorque, self.lastMotorTorque ) + self.lastMissingTorque
	end
end

--**********************************************************************************************************	
-- gearboxMogliMotor:updateGear
--**********************************************************************************************************	
function gearboxMogliMotor:updateGear( acc )
	-- this method is not used here, it is just for convenience 
	if self.vehicle.mrGbMS.ReverseActive then
		acceleration = -acc
	else
		acceleration = acc
	end

	return self:mrGbMUpdateGear( acceleration )
end

--**********************************************************************************************************	
-- gearboxMogliMotor:mrGbMUpdateGear
--**********************************************************************************************************	
function gearboxMogliMotor:mrGbMUpdateGear( accelerationPedalRaw )

	local accelerationPedal = accelerationPedalRaw
	if     accelerationPedalRaw > 1 then
		accelerationPedal = 1
	elseif accelerationPedalRaw > 0 then
		accelerationPedal = accelerationPedalRaw^self.vehicle.mrGbMG.accThrottleExp
	end
	
	local acceleration = math.max( accelerationPedal, 0 )

	if self == nil or self.vehicle == nil then
		local i = 1
		local info 
		print("------------------------------------------------------------------------") 
		while i <= 10 do
			info = debug.getinfo(i) 
			if info == nil then break end
			print(string.format("%i: %s (%i): %s", i, info.short_src, Utils.getNoNil(info.currentline,0), Utils.getNoNil(info.name,"<???>"))) 
			i = i + 1 
		end
		if info ~= nil and info.name ~= nil and info.currentline ~= nil then
			print("...") 
		end
		print("------------------------------------------------------------------------") 
	end
	
	if self.vehicle.mrGbMS.ReverseActive then
		acceleration = -acceleration
	end
	
--**********************************************************************************************************	
-- VehicleMotor.updateGear I
	local requiredWheelTorque = math.huge

	if (0 < acceleration) == (0 < self.gearRatio) then
		requiredWheelTorque = self.requiredWheelTorque
	end

	--local requiredMotorRpm = PowerConsumer.getMaxPtoRpm(self.vehicle)*self.ptoMotorRpmRatio
	local gearRatio          = self:getMogliGearRatio()
	self.lastMaxPossibleRpm  = Utils.getNoNil( self.maxPossibleRpm, self.vehicle.mrGbMS.CurMaxRpm )
	local lastNoTransmission = self.noTransmission
	local lastNoTorque       = self.noTorque 
	self.noTransmission      = false
	self.noTorque            = not ( self.vehicle.isMotorStarted )
	self.maxPossibleRpm      = self.vehicle.mrGbMS.CurMaxRpm
	
--**********************************************************************************************************	

	local currentSpeed       = 3.6 * self.wheelSpeedRpm * gearboxMogli.factorpi30 --3600 * self.vehicle.lastSpeedReal * self.vehicle.movingDirection
	local currentAbsSpeed    = currentSpeed
	if self.vehicle.mrGbMS.ReverseActive then
		currentAbsSpeed        = -currentSpeed
	end
	
--**********************************************************************************************************	
	-- current RPM and power

	self.minRequiredRpm = self.vehicle.mrGbMS.IdleRpm
	
	lastPtoOn  = self.ptoOn
	self.ptoOn = false
	--if self.vehicle.mrGbMS.Hydrostatic then
	
	local handThrottle = -1
	
	if     self.vehicle:mrGbMGetOnlyHandThrottle()
			or self.vehicle.mrGbMS.HandThrottle > 0.01 then
		handThrottle = self.vehicle.mrGbMS.HandThrottle
	end
	
	local handThrottleRpm = self.vehicle.mrGbMS.IdleRpm 
	if handThrottle >= 0 then
		self.ptoOn = true
	--handThrottleRpm     = self.vehicle.mrGbMS.IdleRpm + handThrottle * math.max( 0, self.vehicle.mrGbMS.RatedRpm - self.vehicle.mrGbMS.IdleRpm )
		handThrottleRpm     = self:getThrottleMaxRpm( handThrottle )
		self.minRequiredRpm = math.max( self.minRequiredRpm, handThrottleRpm )
	end
	if self.vehicle.mrGbMS.AllAuto then
		handThrottle = -1
	end
	
	self.lastThrottle = math.max( 0, accelerationPedal )
	
	-- acceleration pedal and speed limit
	local currentSpeedLimit = self.currentSpeedLimit + gearboxMogli.extraSpeedLimitMs
	if self.ptoSpeedLimit ~= nil and currentSpeedLimit > self.ptoSpeedLimit then
		currentSpeedLimit = self.ptoSpeedLimit
	end
		
	local prevWheelSpeedRpm = self.absWheelSpeedRpm
	self.absWheelSpeedRpm = self.wheelSpeedRpm
	if self.vehicle.mrGbMS.ReverseActive then 
		self.absWheelSpeedRpm = -self.absWheelSpeedRpm
	end
	
	self.absWheelSpeedRpm   = math.max( self.absWheelSpeedRpm, 0 )	
	self.absWheelSpeedRpmS  = self.absWheelSpeedRpmS + self.vehicle.mrGbML.smoothFast * ( self.absWheelSpeedRpm - self.absWheelSpeedRpmS )
	local deltaRpm          = ( self.absWheelSpeedRpm - prevWheelSpeedRpm ) / self.tickDt         
	self.deltaRpm           = self.deltaRpm + self.vehicle.mrGbML.smoothMedium * ( deltaRpm - self.deltaRpm )
	local currentPower      = self.usedMotorTorque * math.max( self.prevNonClampedMotorRpm, self.vehicle.mrGbMS.IdleRpm )
	local getMaxPower       = ( self.lastMissingTorque > 0 )
	
	if      self.deltaRpm < -gearboxMogli.autoShiftMaxDeltaRpm 
			and accelerationPedal > 0.9 
			and self.usedTransTorque > self.lastTransTorque - gearboxMogli.eps then
		getMaxPower = true
	end
	
	if      self.vehicle.steeringEnabled
			and self.vehicle.axisForwardIsAnalog
			and accelerationPedal > 0.97 then
		getMaxPower = true
	end
	
	if self.ptoToolTorque > 0 then
		self.ptoOn = true
	end	
	
	self.ptoMotorRpm    = self.vehicle.mrGbMS.IdleRpm
	self.ptoToolRpm     = PowerConsumer.getMaxPtoRpm( self.vehicle )
	self.ptoToolTorque  = PowerConsumer.getTotalConsumedPtoTorque( self.vehicle ) 

	if self.ptoToolTorque > 0 then
		if self.ptoToolRpm == nil or self.ptoToolRpm <= gearboxMogli.eps then
			self.ptoToolRpm = 540
		end
		self.ptoMotorRpm  = Utils.clamp( self.original.ptoMotorRpmRatio * self.ptoToolRpm, self.vehicle.mrGbMS.IdleRpm, self.vehicle.mrGbMS.CurMaxRpm )
	end
			
	if self.vehicle.mrGbMS.IsCombine then
		if self.vehicle:getIsTurnedOn() then
			self.ptoOn          = true
			if self.ptoToolRpm == nil or self.ptoToolRpm <= gearboxMogli.eps then
				self.ptoToolRpm = 540
			end
			local targetRpmC 
			if     handThrottle >= 0 then
				targetRpmC        = Utils.clamp( handThrottleRpm, self.vehicle.mrGbMS.ThreshingMinRpm, self.vehicle.mrGbMS.ThreshingMaxRpm )
			elseif self.lastMissingTorque > 0 then
				targetRpmC        = self.vehicle.mrGbMS.ThreshingMaxRpm
			elseif getMaxPower then
				targetRpmC        = Utils.clamp( self.maxMaxPowerRpm, self.vehicle.mrGbMS.ThreshingMinRpm, self.vehicle.mrGbMS.ThreshingMaxRpm )
			else
				targetRpmC        = self.currentPowerCurve:get( math.max( self.usedMotorTorque, 1.25 * self.ptoMotorTorque ) * math.max( self.prevNonClampedMotorRpm, self.vehicle.mrGbMS.IdleRpm ) )
				targetRpmC        = Utils.clamp( targetRpmC, self.vehicle.mrGbMS.ThreshingMinRpm, self.vehicle.mrGbMS.ThreshingMaxRpm )
			end			
			if handThrottle < 0 then
				targetRpmC = math.min( self.vehicle.mrGbMS.ThreshingMaxRpm, targetRpmC / gearboxMogli.rpmReduction )
			end
			if self.targetRpmC == nil or self.targetRpmC < targetRpmC then
				self.targetRpmC   = targetRpmC 
			else
				self.targetRpmC   = self.targetRpmC + self.vehicle.mrGbML.smoothSlow * ( targetRpmC - self.targetRpmC )		
			end
			self.ptoMotorRpm    = self.targetRpmC
		else
			self.targetRpmC     = nil
		end
	elseif self.ptoToolTorque > 0 then
		self.ptoMotorRpm = self.vehicle.mrGbMS.PtoRpm
		if self.vehicle.mrGbMS.EcoMode then
			self.ptoMotorRpm = self.vehicle.mrGbMS.PtoRpmEco
		end
		-- increase PTO RPM for hydrostatic => less torque needed
		if self.vehicle.mrGbMS.Hydrostatic and self.ptoMotorRpm < self.minRequiredRpm then
			self.ptoMotorRpm = self.minRequiredRpm
		end
		-- reduce PTO RPM in case of hand throttle => more torque needed
		if handThrottle >= 0 and self.ptoMotorRpm > self.minRequiredRpm then
			self.ptoMotorRpm = self.minRequiredRpm
		end
	end

	if self.ptoToolRpm ~= nil and self.ptoToolRpm > 0 then
		self.ptoMotorRpmRatio = self.ptoMotorRpm / self.ptoToolRpm
		self.minRequiredRpm   = math.max( self.minRequiredRpm, self.ptoMotorRpm )
	else
		self.ptoMotorRpmRatio = self.original.ptoMotorRpmRatio
	end

	self.vehicle:mrGbMSetState( "ConstantRpm", self.ptoOn )
	
	local minRpmReduced = Utils.clamp( self.minRequiredRpm * gearboxMogli.rpmReduction, self.vehicle.mrGbMS.CurMinRpm, self.vehicle.mrGbMS.RatedRpm * gearboxMogli.rpmReduction )		

	local rp = math.max( ( self.ptoMotorTorque + self.lastMissingTorque ) * math.max( self.prevNonClampedMotorRpm, self.vehicle.mrGbMS.IdleRpm ), self.lastThrottle * self.currentMaxPower )
	
	if     self.usedTransTorque < self.lastTransTorque - gearboxMogli.eps then
		requestedPower = math.min( rp, currentPower )
	elseif getMaxPower then
		requestedPower = self.currentMaxPower
	elseif rp > currentPower then
		if     self.nonClampedMotorRpm > self.lastCurMaxRpm then
			requestedPower = currentPower
		elseif self.nonClampedMotorRpm + 10 > self.lastCurMaxRpm then
			requestedPower = currentPower + Utils.clamp( 0.1 * ( self.lastCurMaxRpm - self.nonClampedMotorRpm ), 0, 1 ) * ( rp - currentPower )
		elseif self.vehicle.mrGbMS.EcoMode then
			requestedPower = math.min( 0.9*rp, 1.11 * currentPower )
		else
			requestedPower = rp
		end
	else
		requestedPower = currentPower
	end

--print(string.format( "%3.0f%% %4.0f %4.0f %4.0f %4.0f => %4.0f ", self.lastThrottle*100, currentPower, pp, rp, self.currentMaxPower, requestedPower )..tostring(getMaxPower))
	
	self.motorLoadP = 0
	
	if     not ( self.vehicle.isMotorStarted ) then
		self.motorLoadS1 = nil
		self.motorLoadP = 0
	elseif self.lastRealMotorRpm >= self.vehicle.mrGbMS.CurMaxRpm or self.lastMotorTorque < gearboxMogli.eps then
		self.motorLoadP = 0
	else
		self.motorLoadP = self.usedMotorTorque / self.lastMotorTorque
	end

	if     self.prevMotorRpm > self.vehicle.mrGbMS.RatedRpm and self.lastMotorTorque * self.prevMotorRpm  < self.maxRatedTorque * self.vehicle.mrGbMS.RatedRpm then
		self.motorLoadP = 0.2 * self.motorLoadP + 0.8 * self.usedMotorTorque * self.prevMotorRpm / ( self.maxRatedTorque * self.vehicle.mrGbMS.RatedRpm )
	elseif self.lastMissingTorque > 0 and self.motorLoadP < 1 then
		self.motorLoadP = 1
	elseif lastNoTorque then
		self.motorLoadP = 0
	end

	if self.requestedPower1 == nil then
		self.requestedPower1 = requestedPower
	else
		local slow = self.vehicle.mrGbMG.dtDeltaTargetSlow * self.tickDt * self.currentMaxPower
		local fast = self.vehicle.mrGbMG.dtDeltaTargetFast * self.tickDt * self.currentMaxPower
		
		self.requestedPower1 = self.requestedPower1 + Utils.clamp( requestedPower - self.requestedPower1, -slow, fast )
	end
  self.requestedPower = self.requestedPower1
	
	if self.motorLoadS1 == nil then
		self.motorLoadS1 = self.motorLoadP
		self.motorLoadS2 = self.motorLoadP
		self.motorLoadP  = Utils.clamp( self.motorLoadP, 0, 1 )
		self.motorLoadS	 = self.motorLoadP
	else
		local slow = self.vehicle.mrGbMG.dtDeltaTargetSlow * self.tickDt
		local fast = self.vehicle.mrGbMG.dtDeltaTargetFast * self.tickDt
		
		self.motorLoadS1 = self.motorLoadS1 + Utils.clamp( self.motorLoadP - self.motorLoadS1, -fast, fast )	
		self.motorLoadS2 = self.motorLoadS2 + Utils.clamp( self.motorLoadP - self.motorLoadS2, -slow, slow )
		
		self.motorLoadS	 = Utils.clamp( math.max( self.motorLoadS1, self.motorLoadS2 ), 0, 1 )	
		self.motorLoadP  = Utils.clamp( self.motorLoadP, 0, 1 )
  end		

	local mlf = Utils.clamp( 1 - ( 1 - self.motorLoadP )^gearboxMogli.motorLoadExp, 0, 1 ) 
	if     self.vehicle.mrGbML.gearShiftingNeeded == 2
			or ( self.vehicle.mrGbML.gearShiftingNeeded > 0 and self.vehicle.mrGbML.doubleClutch )
			or self.vehicle.mrGbML.gearShiftingNeeded  < 0 then
		mlf = math.max( 0.5, mlf )
	end
	if  not lastNoTransmission
			and self.nonClampedMotorRpm > self.prevNonClampedMotorRpm + self.maxRpmIncrease - gearboxMogli.eps then
		mlf = math.max( 0.9 * accelerationPedal, mlf )
	end
	self.motorLoad = math.max( 0, self.maxMotorTorque * mlf - self.ptoToolTorque / self.ptoMotorRpmRatio )
	
	local wheelLoad    = 0
	local acceleration = 0
	if not ( lastNoTransmission ) then
		wheelLoad        = math.abs( self.usedTransTorque * self.gearRatio	)
	end
	if self.wheelLoadS == nil then
		self.wheelLoadS  = wheelLoad
	else
		self.wheelLoadS  = self.wheelLoadS + self.vehicle.mrGbML.smoothFast * ( wheelLoad - self.wheelLoadS )		
  end		
	if self.accelerationS == nil then
		self.accelerationS = 0
	elseif wheelLoad > 0 then
		if self.tickDt > 0 then
			acceleration     = ( self.vehicle.lastSpeedReal*1000 - self.lastLastSpeed ) * 1000 / self.tickDt 
		end
		self.accelerationS = self.accelerationS + self.vehicle.mrGbML.smoothFast * ( acceleration - self.accelerationS )	
	end
	self.lastLastSpeed    = self.vehicle.lastSpeedReal*1000
	
	local targetRpm = self.minRequiredRpm
	local minTarget = minRpmReduced	
	
	if self.ptoOn then
		if self.vehicle.mrGbMS.Hydrostatic then
			-- PTO or hand throttle 
			minTarget = self.minRequiredRpm
		else
		-- reduce target RPM to accelerate and increase to brake 
			targetRpm = Utils.clamp( self.minRequiredRpm - accelerationPedal * gearboxMogli.ptoRpmThrottleDiff, minRpmReduced, self.vehicle.mrGbMS.MaxTargetRpm )
		end			
	else
		if     lastNoTransmission then
		-- no transmission 
			targetRpm = self.minRequiredRpm
		elseif accelerationPedal <= -0.5 -gearboxMogli.accDeadZone then
		-- motor brake
			targetRpm = self.vehicle.mrGbMS.RatedRpm
		elseif accelerationPedal < -gearboxMogli.accDeadZone then
		-- motor brake
			targetRpm = self.vehicle.mrGbMS.IdleRpm + 2 * ( 0.2 + accelerationPedal ) * ( self.vehicle.mrGbMS.RatedRpm - self.vehicle.mrGbMS.IdleRpm )
		else
			targetRpm = Utils.clamp( self.currentPowerCurve:get( requestedPower ), self.minRequiredRpm, self.vehicle.mrGbMS.MaxTargetRpm )
		end

		if minRpmReduced < self.vehicle.mrGbMS.MinTargetRpm then
			if     accelerationPedal > gearboxMogli.accDeadZone then
				minTarget = self.vehicle.mrGbMS.MinTargetRpm
			elseif currentAbsSpeed < gearboxMogli.eps then
				minTarget = minRpmReduced
			elseif currentAbsSpeed < 2 then
				minTarget = minRpmReduced + ( self.vehicle.mrGbMS.MinTargetRpm - minRpmReduced ) * currentAbsSpeed * 0.5 
			else
				minTarget = self.vehicle.mrGbMS.MinTargetRpm
			end
		end
		if targetRpm < minTarget then
			targetRpm = minTarget	
		elseif self.vehicle.cruiseControl.state ~= 0
				or not self.vehicle.steeringEnabled then
		-- nothing
		elseif gearboxMogli.eps < accelerationPedal and accelerationPedal < self.vehicle.mrGbMS.MaxRpmThrottle then
			local tr = self:getThrottleMaxRpm( accelerationPedal / self.vehicle.mrGbMS.MaxRpmThrottle )
			if     tr < minTarget then
				targetRpm = minTarget 
			elseif tr > targetRpm then
				targetRpm = tr
			end
		end
	end
	
	-- smooth
	if self.targetRpm1 == nil then
		self.targetRpm1 = targetRpm 
	else
		local slow = self.vehicle.mrGbMG.dtDeltaTargetSlow * self.tickDt * ( self.maxPowerRpm - self.vehicle.mrGbMS.MinTargetRpm )
		local fast = self.vehicle.mrGbMG.dtDeltaTargetFast * self.tickDt * ( self.maxPowerRpm - self.vehicle.mrGbMS.MinTargetRpm )
		
		self.targetRpm1 = self.targetRpm1 + Utils.clamp( targetRpm - self.targetRpm1, -slow, fast )		
  end		
	
--print(string.format("%3d%%, %6g, %6g, %3d%%, %4d, %4d, %4d",
--										accelerationPedal*100,
--										self.usedTransTorque,
--										self.lastTransTorque,
--										requestedPower/self.currentMaxPower*100,
--										targetRpm,
--										self.targetRpm1,
--										self.targetRpm))
												
	self.targetRpm = self.targetRpm1
	
	-- clutch calculations...
	local clutchMode = 0 -- no clutch calculation

	if self.lastClutchClosedTime < self.vehicle.mrGbML.autoShiftTime then
		self.lastClutchClosedTime = self.vehicle.mrGbML.autoShiftTime
	end
	
  local r = self.vehicle.mrGbMS.RpmIncFactor + self.motorLoadP * self.motorLoadP * ( self.vehicle.mrGbMS.RpmIncFactorFull - self.vehicle.mrGbMS.RpmIncFactor )
  self.rpmIncFactor   = self.rpmIncFactor + self.vehicle.mrGbML.smoothMedium * ( r - self.rpmIncFactor )
	self.maxRpmIncrease = self.tickDt * self.rpmIncFactor
			
--**********************************************************************************************************		
	local oldAccTimer = self.hydroAccTimer
	self.hydroAccTimer = nil
	
	local maxDeltaThrottle = self.vehicle.mrGbMG.maxDeltaAccPerMs * self.tickDt 

--**********************************************************************************************************		
-- no transmission / neutral 
--**********************************************************************************************************		
	local brakeNeutral   = false
	local autoOpenClutch = ( self.vehicle.mrGbMS.Hydrostatic and self.vehicle.mrGbMS.HydrostaticLaunch )
											or ( ( self.vehicle:mrGbMGetAutoClutch() or self.vehicle.mrGbMS.TorqueConverter )
											 and accelerationPedal < -0.001 )
	
	if      self.vehicle.mrGbMS.Hydrostatic
			and self.ptoOn 
			and not ( self.vehicle.mrGbML.ReverserNeutral )
			and accelerationPedal < -0.5
			and currentAbsSpeed >= self.vehicle.mrGbMG.minAbsSpeed then
		autoOpenClutch = false
	end
	
	if     self.vehicle.mrGbMS.G27Mode > 0 
			or not self.vehicle.mrGbMS.NeutralActive 
			or self.vehicle:getIsHired() then
		if     accelerationPedal >= -0.001 
				or currentAbsSpeed   >= self.vehicle.mrGbMG.minAbsSpeed then
			self.brakeNeutralTimer = g_currentMission.time + self.vehicle.mrGbMG.brakeNeutralTimeout
		end
	else
		if accelerationPedal > 0.001 then
			self.brakeNeutralTimer = g_currentMission.time + self.vehicle.mrGbMG.brakeNeutralTimeout
		end
	end
	
	if     self.vehicle.mrGbMS.NeutralActive
			or self.vehicle.mrGbMS.G27Mode == 1
			or not ( self.vehicle.isMotorStarted ) 
			or g_currentMission.time < self.vehicle.motorStartTime then
	-- off or neutral
		brakeNeutral = true
	elseif  self.vehicle.mrGbML.ReverserNeutral
			and autoOpenClutch
			and currentAbsSpeed < -1.8 then
	-- reverser and did not stop yet
		brakeNeutral = true
	elseif  self.vehicle.mrGbMS.Hydrostatic
			and self.vehicle.mrGbMS.HydrostaticMin < gearboxMogli.eps
			and accelerationPedal >= -0.001 then
		brakeNeutral = false
--elseif  currentAbsSpeed < -1.8 
--		and math.abs( self.vehicle.lastSpeedReal * 3600 ) > 1
--		and autoOpenClutch 
--		and not self.vehicle.mrGbMS.TorqueConverterOrHydro then
--	brakeNeutral  = true 
--	self.noTorque = true
	elseif self.vehicle.cruiseControl.state ~= 0 
			or not autoOpenClutch then
	-- no automatic stop or cruise control is on 
		brakeNeutral = false
	elseif accelerationPedal >= -0.001 then
	-- not braking 
		if      accelerationPedal            <  0.1
				and self.clutchRpm               <  0
				and self.vehicle:mrGbMGetAutoStartStop() 
				and self.vehicle.mrGbMS.G27Mode  <= 0 
				and not self.vehicle.mrGbMS.TorqueConverterOrHydro then				
	-- idle
			brakeNeutral = true 
		else
			brakeNeutral = false
		end
	elseif currentAbsSpeed       < self.vehicle.mrGbMG.minAbsSpeed + self.vehicle.mrGbMG.minAbsSpeed 
			or self.lastMotorRpm     < minRpmReduced 
			or ( self.lastMotorRpm   < self.minRequiredRpm and self.minThrottle > 0.2 ) then
	-- no transmission 
		brakeNeutral = true 
	else
		brakeNeutral = false
	end
	
	if self.vehicle.mrGbMG.debugInfo then
		self.vehicle.mrGbML.brakeNeutralInfo = 
			string.format("%1.3f %4d %s %2.1f %4d %4d", accelerationPedal, self.brakeNeutralTimer - g_currentMission.time, tostring(brakeNeutral), currentAbsSpeed, self.lastMotorRpm, self.minRequiredRpm)
	end
		
	if brakeNeutral then
	-- neutral	
	
	--print("neutral: "..tostring(self.clutchRpm).." "..tostring(currentAbsSpeed))
	
		if  not ( self.vehicle.mrGbMS.NeutralActive ) 
				and self.vehicle:mrGbMGetAutoStartStop()
				and self.vehicle.mrGbMS.G27Mode <= 0
				and self.brakeNeutralTimer  < g_currentMission.time
				and ( currentAbsSpeed       < self.vehicle.mrGbMG.minAbsSpeed
					 or ( self.lastMotorRpm   < minRpmReduced and not self.vehicle:mrGbMGetAutomatic() ) ) then
			self.vehicle:mrGbMSetNeutralActive( true ) 
		end
	-- handbrake 
		if      self.vehicle.mrGbMS.NeutralActive 
				and self.vehicle:mrGbMGetAutoHold( )
				and self.brakeNeutralTimer  < g_currentMission.time then
			self.vehicle:mrGbMSetState( "AutoHold", true )
		end
				
		if self.vehicle.mrGbMS.Hydrostatic and self.vehicle.mrGbMS.HydrostaticLaunch then
		elseif self.vehicle:mrGbMGetAutoClutch() then
			self.autoClutchPercent  = math.max( 0, self.autoClutchPercent -self.tickDt/self.vehicle.mrGbMS.ClutchTimeDec ) 
			self.vehicle:mrGbMSetState( "IsNeutral", true )
		elseif self.vehicle.mrGbMS.ManualClutch > 0.9 then
			self.vehicle:mrGbMSetState( "IsNeutral", true )
		end
		
		if     self.vehicle.mrGbML.gearShiftingNeeded == gearboxMogli.gearShiftingNoThrottle then
			self.vehicle:mrGbMDoGearShift() 
			self.vehicle.mrGbML.gearShiftingNeeded = 0 
		elseif self.vehicle.mrGbML.gearShiftingNeeded > 0 then
			if g_currentMission.time>=self.vehicle.mrGbML.gearShiftingTime then
				if self.vehicle.mrGbML.gearShiftingNeeded < 2 then	
					self.vehicle:mrGbMDoGearShift() 
				end 
				self.vehicle.mrGbML.gearShiftingNeeded = 0 
			elseif self.vehicle.mrGbML.gearShiftingNeeded < 2 then	
				if self.autoClutchPercent <= 0 then
					self.vehicle:mrGbMDoGearShift() 
				end 
			end 
		end

		self.noTransmission  = true
		self.requestedPower1 = nil
		
		if      self.vehicle.mrGbMS.Hydrostatic 
				and self.targetRpm > gearboxMogli.eps
				and self.hydrostaticFactorT ~= nil then
			local hTgt = self.absWheelSpeedRpm * self:getMogliGearRatio() / self.targetRpm 
			
			if     self.vehicle.mrGbMS.HydrostaticMin >= 0 then
				hTgt = Utils.clamp( hTgt, self.vehicle.mrGbMS.HydrostaticStart, self.vehicle.mrGbMS.HydrostaticMax ) 
			elseif self.vehicle.mrGbMS.ReverseActive then	
				hTgt = Utils.clamp( hTgt, self.vehicle.mrGbMS.HydrostaticStart, -self.vehicle.mrGbMS.HydrostaticMin ) 
			else
				hTgt = Utils.clamp( hTgt, self.vehicle.mrGbMS.HydrostaticStart,  self.vehicle.mrGbMS.HydrostaticMax ) 
			end
			
			if math.abs( hTgt - self.hydrostaticFactorT ) > gearboxMogli.eps then
				if hTgt > self.hydrostaticFactorT then
					self.hydrostaticFactorT = self.hydrostaticFactorT + math.min( hTgt - self.hydrostaticFactorT,  self.tickDt * self.vehicle.mrGbMS.HydrostaticIncFactor ) 		
				else
					self.hydrostaticFactorT = self.hydrostaticFactorT + math.max( hTgt - self.hydrostaticFactorT, -self.tickDt * self.vehicle.mrGbMS.HydrostaticDecFactor )
				end
			end					
		end
					
--**********************************************************************************************************		
	else
--**********************************************************************************************************		
		self.vehicle:mrGbMSetState( "IsNeutral", false )
		self.vehicle.mrGbML.ReverserNeutral = false
		
		-- acceleration for idle/minimum rpm				
		if      self.vehicle.mrGbMS.Hydrostatic 
				and self.vehicle.mrGbMS.HydrostaticMin < gearboxMogli.minHydrostaticFactor then
			self.minThrottle  = 0
		elseif lastNoTransmission then
			self.minThrottle  = math.max( 0.2, self.vehicle.mrGbMS.HandThrottle )
			self.targetRpm    = minRpmReduced
		else
			local mt = 0
		
			local minThrottleRpm = minRpmReduced 
			if handThrottle > 0 then
				minThrottleRpm = Utils.clamp( handThrottleRpm - gearboxMogli.ptoRpmThrottleDiff, minRpmReduced, self.minRequiredRpm )
			end
			if     self.nonClampedMotorRpm <= minThrottleRpm then
				mt  = 1
			elseif self.nonClampedMotorRpm < self.minRequiredRpm then
				mt = ( self.minRequiredRpm - self.nonClampedMotorRpm ) / ( self.minRequiredRpm - minThrottleRpm )
			else
				mt = 0
			end	
			
			mt = 0.5 * mt
			
			self.minThrottle = Utils.clamp( self.minThrottle + Utils.clamp( mt - self.minThrottle, -maxDeltaThrottle, maxDeltaThrottle ), 0, 1 )
		end
		
		self.lastThrottle = math.max( self.minThrottle, accelerationPedal )								
		
		if     self.vehicle.mrGbML.gearShiftingNeeded == gearboxMogli.gearShiftingNoThrottle then
	--**********************************************************************************************************		
	-- during gear shift with release throttle 
			if     self.vehicle:mrGbMGetAutoClutch() then
				if g_currentMission.time >= self.vehicle.mrGbML.gearShiftingTime then
					self.vehicle:mrGbMDoGearShift() 
					self.vehicle.mrGbML.gearShiftingNeeded = 0
				end
				accelerationPedal = 0
				self.noTorque     = true
			elseif ( accelerationPedal < 0.1 and self.vehicle.cruiseControl.state == 0 )
					or self.vehicle.mrGbMS.ManualClutch < self.vehicle.mrGbMS.MinClutchPercent + 0.1 then
				self.vehicle:mrGbMDoGearShift() 
				self.vehicle.mrGbML.gearShiftingNeeded = 0 
			end			

			self.lastClutchClosedTime = g_currentMission.time
			self.deltaRpm = 0
			
		elseif self.vehicle.mrGbML.gearShiftingNeeded > 0 then
	--**********************************************************************************************************		
	-- during gear shift with automatic clutch
			if self.vehicle.mrGbML.gearShiftingNeeded == 2 and g_currentMission.time < self.vehicle.mrGbML.gearShiftingTime then	
				if self.lastRealMotorRpm > 0.97 * self.vehicle.mrGbMS.RatedRpm then
					self.vehicle.mrGbML.gearShiftingNeeded  = 3
				end
				accelerationPedal = 1
			else               
				accelerationPedal = 0
				self.noTorque     = true
			end

			if g_currentMission.time >= self.vehicle.mrGbML.gearShiftingTime then
				if self.vehicle.mrGbML.gearShiftingNeeded < 2 then	
					self.vehicle:mrGbMDoGearShift() 
				end 
				self.vehicle.mrGbML.gearShiftingNeeded = 0 
				self.maxPossibleRpm          = self.vehicle.mrGbMS.CurMaxRpm 
				self.vehicle.mrGbML.manualClutchTime = 0
				clutchMode                   = 2 
			elseif self.vehicle.mrGbML.gearShiftingNeeded < 2 then	
				if self.autoClutchPercent > 0 and g_currentMission.time < self.vehicle.mrGbML.clutchShiftingTime then
					self.autoClutchPercent   = Utils.clamp( ( self.vehicle.mrGbML.clutchShiftingTime - g_currentMission.time )/self.vehicle.mrGbMS.ClutchShiftTime, 0, self.autoClutchPercent ) 					
				else
					self.vehicle:mrGbMDoGearShift() 
					self.noTransmission = true
				end 
			else
				self.noTransmission = true
			end 
			self.prevNonClampedMotorRpm = self.vehicle.mrGbMS.CurMaxRpm
			self.extendAutoShiftTimer   = true
			
			self.lastClutchClosedTime = g_currentMission.time
			self.deltaRpm = 0
			
		elseif self.vehicle.mrGbML.gearShiftingNeeded < 0 then
	--**********************************************************************************************************		
	-- during gear shift with manual clutch
			self.noTransmission = true			
			self.vehicle:mrGbMDoGearShift() 
			self.vehicle.mrGbML.gearShiftingNeeded = 0						
			
			self.lastClutchClosedTime = g_currentMission.time
			self.deltaRpm = 0
			
		elseif not ( self.vehicle:mrGbMGetAutoClutch() ) and self.vehicle.mrGbMS.ManualClutch < gearboxMogli.minClutchPercent then
	--**********************************************************************************************************		
	-- manual clutch pressed
			self.noTransmission = true		
			self.lastClutchClosedTime = g_currentMission.time
			self.deltaRpm = 0
			
		else
	--**********************************************************************************************************		
	-- normal drive with gear and clutch
			self.noTransmission = false

			local accHydrostaticTarget = false

	--**********************************************************************************************************		
	-- reduce hydrostaticFactor instead of braking  
			if      self.vehicle.mrGbMS.Hydrostatic
					and self.ptoOn then
				accHydrostaticTarget = true			
			end
			
	--**********************************************************************************************************		
	-- no transmission while braking 
			if      self.vehicle.cruiseControl.state == 0 
					and self.vehicle.steeringEnabled
					and autoOpenClutch 
					and accelerationPedal       < self.vehicle.mrGbMG.brakeNeutralLimit 
					and self.nonClampedMotorRpm < self.minRequiredRpm
					and ( self.vehicle.axisForwardIsAnalog 
						or not accHydrostaticTarget
						or currentAbsSpeed       < self.vehicle.mrGbMG.minAbsSpeed ) then
				self.noTransmission = true
				self.lastClutchClosedTime = self.vehicle.mrGbML.autoShiftTime
			end
		
			clutchMode = 1 -- calculate clutch percent respecting inc/dec time ms

	--**********************************************************************************************************		
	-- hydrostatic drive
			if self.vehicle.mrGbMS.Hydrostatic then
				-- target RPM
				local c = self.lastRealMotorRpm 
				local t = self.targetRpm
				local a = math.min( accelerationPedal, self.lastThrottle )
				
				-- boundaries hStart, hMin & hMax
				local hMax = self.vehicle.mrGbMS.HydrostaticMax			
				-- find the best hMin
				local hMin = self.vehicle.mrGbMS.HydrostaticMin 
				
				if self.vehicle.mrGbMS.HydrostaticMin < 0 then
					if self.vehicle.mrGbMS.HydrostaticMin < 0 and self.vehicle.mrGbMS.ReverseActive then	
						hMax = -self.vehicle.mrGbMS.HydrostaticMin 
					end
					hMin = 0 --gearboxMogli.eps
				end
				
				local w0   = self.absWheelSpeedRpm
				local wMin = self.absWheelSpeedRpm + math.min( 0, self.absWheelSpeedRpm - prevWheelSpeedRpm )
				local wMax = self.absWheelSpeedRpm + math.max( 0, self.absWheelSpeedRpm - prevWheelSpeedRpm )
				
				local hFix = -1
				if not self.ptoOn and self.vehicle.mrGbMS.FixedRatio > gearboxMogli.eps then
					hFix = self.vehicle.mrGbMS.FixedRatio * hMax
				end
				
				if self.vehicle:mrGbMGetAutomatic() then
					local gearMaxSpeed = self.vehicle.mrGbMS.Ranges2[self.vehicle.mrGbMS.CurrentRange2].ratio
														 * self.vehicle.mrGbMS.GlobalRatioFactor
					if self.vehicle.mrGbMS.ReverseActive then	
						gearMaxSpeed = gearMaxSpeed * self.vehicle.mrGbMS.ReverseRatio 
					end
					
					local currentGear = self:combineGear()
					local maxGear
					if     not self.vehicle:mrGbMGetAutoShiftRange() then
						maxGear = table.getn( self.vehicle.mrGbMS.Gears )
					elseif not self.vehicle:mrGbMGetAutoShiftGears() then 
						maxGear = table.getn( self.vehicle.mrGbMS.Ranges )
					else
						maxGear = table.getn( self.vehicle.mrGbMS.Gears ) * table.getn( self.vehicle.mrGbMS.Ranges )
					end
					
					local refTime   = self.lastClutchClosedTime
					local downTimer = refTime + self.vehicle.mrGbMS.AutoShiftTimeoutShort
					local upTimer   = refTime + self.vehicle.mrGbMS.AutoShiftTimeoutShort
					
					local bestE     = nil
					local bestR     = nil
					local bestS     = nil
					local bestG     = currentGear
					local bestH     = self.hydrostaticFactorT
					local tooBig    = false
					local tooSmall  = false
					
					if      self.vehicle.cruiseControl.state > 0 
							and self.vehicle.mrGbMS.CurrentGearSpeed * self.vehicle.mrGbMS.IdleRpm / self.vehicle.mrGbMS.RatedRpm > currentSpeedLimit then
						-- allow down shift after short timeout
					elseif self.vehicle.mrGbML.lastGearSpeed < self.vehicle.mrGbMS.CurrentGearSpeed + gearboxMogli.eps then
						downTimer = refTime + self.vehicle.mrGbMS.AutoShiftTimeoutLong 
					elseif self.vehicle.mrGbML.lastGearSpeed > self.vehicle.mrGbMS.CurrentGearSpeed + gearboxMogli.eps then
						if      accelerationPedal       > 0.5
								and self.nonClampedMotorRpm > self.vehicle.mrGbMS.RatedRpm then
							-- allow up shift after short timeout
							upTimer   = refTime -- + self.vehicle.mrGbMS.AutoShiftTimeoutShort
						else
							upTimer   = refTime + self.vehicle.mrGbMS.AutoShiftTimeoutLong 
						end
					elseif self.hydrostaticFactor > hMax - gearboxMogli.eps then
						upTimer   = math.min( refTime + self.vehicle.mrGbMS.AutoShiftTimeoutShort, upTimer )
					elseif self.hydrostaticFactor < self.vehicle.mrGbMS.HydrostaticStart - gearboxMogli.eps then
						downTimer = math.min( refTime + self.vehicle.mrGbMS.AutoShiftTimeoutShort, downTimer )
					end		
					
					local spdFix = -1
					if hFix > 0 then
						local i2g, i2r = self:splitGear( maxGear )
						spdFix =    self.vehicle.mrGbMS.Gears[i2g].speed
											* self.vehicle.mrGbMS.Ranges[i2r].ratio
											* gearMaxSpeed 
											* hFix
					end
					
					for g=1,maxGear do
						local isValidEntry = true
						local i2g, i2r = self:splitGear( g )
					
						if isValidEntry and self.vehicle:mrGbMGetAutoShiftGears() and gearboxMogli.mrGbMIsNotValidEntry( self.vehicle, self.vehicle.mrGbMS.Gears[i2g], i2g, i2r ) then
							isValidEntry = false
						end
						if isValidEntry and self.vehicle:mrGbMGetAutoShiftRange() and gearboxMogli.mrGbMIsNotValidEntry( self.vehicle, self.vehicle.mrGbMS.Ranges[i2r], i2g, i2r ) then
							isValidEntry = false
						end
					
						local spd = self.vehicle.mrGbMS.Gears[i2g].speed
											* self.vehicle.mrGbMS.Ranges[i2r].ratio
											* gearMaxSpeed 
											
						if spdFix > 0 then
							local h = spdFix / spd
							if h > hMax or h < hMin then
								isValidEntry = false
							end
						end
												
						if g ~= currentGear then						
							if not isValidEntry then
							-- nothing 
							elseif self.vehicle.mrGbMS.AutoShiftTimeoutLong > 0 then								
								local autoShiftTimeout = 0
								if     spd < self.vehicle.mrGbMS.CurrentGearSpeed - gearboxMogli.eps then
									autoShiftTimeout = downTimer							
								elseif spd > self.vehicle.mrGbMS.CurrentGearSpeed + gearboxMogli.eps then
									autoShiftTimeout = upTimer
								else
									autoShiftTimeout = math.min( downTimer, upTimer )
								end
								
								autoShiftTimeout = autoShiftTimeout + self.vehicle.mrGbMS.GearTimeToShiftGear
								
								if autoShiftTimeout > g_currentMission.time then
									if gearboxMogli.debugGearShift then print(tostring(g)..": Still waiting") end
									isValidEntry = false
								end
							end
							
							if not isValidEntry then
							--nothing
							elseif  accelerationPedal < -gearboxMogli.accDeadZone
							    and spd           > self.vehicle.mrGbMS.CurrentGearSpeed + gearboxMogli.eps then
								if gearboxMogli.debugGearShift then print(tostring(g)..": no down shift I") end
								isValidEntry = false
							elseif  self.deltaRpm < -gearboxMogli.autoShiftMaxDeltaRpm
									and spd           > self.vehicle.mrGbMS.CurrentGearSpeed + gearboxMogli.eps then
								if gearboxMogli.debugGearShift then print(tostring(g)..": no down shift II") end
								isValidEntry = false
							elseif  self.deltaRpm > gearboxMogli.autoShiftMaxDeltaRpm
									and spd           < self.vehicle.mrGbMS.CurrentGearSpeed - gearboxMogli.eps then
								if gearboxMogli.debugGearShift then print(tostring(g)..": no up shift III") end
								isValidEntry = false
							end
						end

						if isValidEntry then	
							local r = gearboxMogli.gearSpeedToRatio( self.vehicle, spd )					
							local w = w0 * r
					
							if w <= gearboxMogli.eps then
								if bestS == nil or bestS > spd then
									bestS = spd
									bestG = g
									bestR = 9999
									bestE = -1
									bestH = self.vehicle.mrGbMS.HydrostaticStart
								end
							else
								local h = w / t
								
								if hMin <= h and h <= hMax then
									local e = self:getHydroEff( h )
									if bestS == nil or bestR > 0 or bestE < e then
										bestG = g
										bestS = spd
										bestE = e
										bestR = 0
										bestH = h
									end
								elseif bestS == nil or bestR > 0 then
									local r = math.abs( t - w / Utils.clamp( h, math.max( hMin, gearboxMogli.eps ), hMax ) )
									if bestE == nil or bestR > r then
										bestG = g
										bestS = spd
										bestE = 0
										bestR = r
										bestH = h
									end
								end
							end
						end
					end
					
					if self.vehicle.mrGbMG.debugInfo then
						self.vehicle.mrGbML.autoShiftInfo = string.format( "rpm: %4.0f target: %4.0f gear: %2d speed: %5.3f hydro: %4.2f\n",
																																self.lastRealMotorRpm, 
																																t, 
																																currentGear, 
																																self.vehicle.mrGbMS.CurrentGearSpeed,
																																self.hydrostaticFactor )
					end
					
					if bestS == nil then
						if self.vehicle.mrGbMG.debugInfo then
							self.vehicle.mrGbML.autoShiftInfo = self.vehicle.mrGbML.autoShiftInfo .. "nothing found: "..tostring(tooBig).." "..tostring(tooSmall)
						end
					else
						if self.vehicle.mrGbMG.debugInfo then
							self.vehicle.mrGbML.autoShiftInfo = self.vehicle.mrGbML.autoShiftInfo ..
																									string.format( "bestG: %2d bestS: %5.3f bestE: %4.2f bestR: %4.0f",
																																	bestG, bestS, bestE, bestR )
						end
						if spdFix > 0 then
							hFix = spdFix / bestS 
						end
					end 
					
					if bestG ~= currentGear then	
						local i2g, i2r = self:splitGear( bestG )
						
						if self.vehicle.mrGbML.autoShiftInfo ~= nil and ( self.vehicle.mrGbMG.debugPrint or gearboxMogli.debugGearShift ) then
							print(self.vehicle.mrGbML.autoShiftInfo)
							print("-------------------------------------------------------")
						end
						
						if self.vehicle:mrGbMGetAutoShiftGears() then
							self.vehicle:mrGbMSetCurrentGear( i2g ) 
						end
						if self.vehicle:mrGbMGetAutoShiftRange() then
							self.vehicle:mrGbMSetCurrentRange( i2r ) 
						end
						clutchMode                           = 2
						self.vehicle.mrGbML.manualClutchTime = 0
						self.hydrostaticFactorT = bestH
					end
				end

				
				if self.vehicle.mrGbML.gearShiftingNeeded == 0 then
					-- min RPM
					local r = self:getMogliGearRatio()
					local w = w0 * r
					
					-- min / max RPM
					local n0 = minTarget
					local m0 = math.min( self.vehicle.mrGbMS.HydrostaticMaxRpm, self:getThrottleMaxRpm( a / self.vehicle.mrGbMS.MaxRpmThrottle ) ) 
					
					if hFix > 0 then
						n0 = self.vehicle.mrGbMS.IdleRpm
					end
					
					if self.torqueRpmReduction ~= nil then
						n0 = math.min( n0, self.torqueRpmReference - self.torqueRpmReduction )
						m0 = math.min( m0, self.torqueRpmReference - self.torqueRpmReduction )
						t  = math.min( t,  self.torqueRpmReference - self.torqueRpmReduction )
					end
										
					local d = gearboxMogli.hydroEffDiff
					if d < gearboxMogli.huge and gearboxMogli.hydroEffDiffInc > 0 then
						d = d + math.min(1,1.4-1.4*self.motorLoadS) * gearboxMogli.hydroEffDiffInc
					end
					
					if self.ptoOn and d > self.vehicle.mrGbMS.HydrostaticPtoDiff then
						d = self.vehicle.mrGbMS.HydrostaticPtoDiff
					end
					
					local m1    = Utils.clamp( t + d, n0, m0 )
					local n1    = Utils.clamp( t - d, n0, m0 )					
					local hMin1 = Utils.clamp( w / m1, hMin, hMax )
					local hMax1 = Utils.clamp( w / n1, hMin, hMax )
					local hTgt  = Utils.clamp( w / t, hMin1, hMax1 )

					if     hFix > 0 then
						hTgt = math.max( hMin, hFix )
					elseif hMin1 > hMax1 - gearboxMogli.eps then
						hTgt = hMin1
					elseif self.ptoOn and ( self.vehicle.cruiseControl.state == Drivable.CRUISECONTROL_STATE_ACTIVE or self.vehicle.mrGbML.hydroTargetSpeed ~= nil ) then					
						hTgt = Utils.clamp( self.vehicle.mrGbMS.RatedRpm * currentSpeedLimit / ( t * self.vehicle.mrGbMS.CurrentGearSpeed ), hMin1, hMax1 )						
					elseif not ( self.vehicle.mrGbMS.HydrostaticDirect ) then
						local sp = nil
						local sf = nil						
						local ti = Utils.clamp( math.floor( 200 * ( hMax1 - hMin1 ) + 0.5 ), 10, 100 )
						local td = 1 / ti
						
						for f=0,ti do
							local h2 = hMax1 + f * ( hMin1 - hMax1 ) * td
							local r2 = w / math.max( h2, gearboxMogli.eps )
													
							local mt = self.currentTorqueCurve:get( r2 )
							if mt > gearboxMogli.eps and mt > self.ptoMotorTorque then
								local e  = self:getHydroEff( h2 )
								local rt = a * ( mt - self.ptoMotorTorque ) 
								local lt = Utils.clamp( 1 - e, 0, 1 ) * rt
								rt = rt - lt
								if self.usedTransTorque < rt and self.usedTransTorque < self.lastTransTorque - gearboxMogli.eps then
									rt = self.usedTransTorque 
								end
								
								local ratio = self.fuelCurve:get( r2 ) / gearboxMogli.powerFuelCurve:get( ( rt + self.ptoMotorTorque + lt ) / mt )
								local rp = ( rt + self.ptoMotorTorque + lt ) * r2
								local dp = math.max( 0, requestedPower - mt * r2 )
								local df = ratio * rp
																
								if     sp == nil 
										or dp < sp 
										or ( dp == sp and df < sf ) then
									sp   = dp
									sf   = df 
									hTgt = h2
								end
							end
						end
					end
					
					if gearboxMogli.debugGearShift and self.torqueRpmReduction ~= nil then
						print(string.format("torqueRpmReduction r: %4d n: %4d m: %4d t: %4d / h: %6f t: %6f / %6f / %6f",
																self.torqueRpmReference - self.torqueRpmReduction,
																n1,
																m1,
																t,
																self.hydrostaticFactor,
																hTgt,
																currentSpeedLimit*3.6,
																self.vehicle.lastSpeedReal*3600))
					end
					
					if     self.hydrostaticFactorT == nil 
							or self.torqueRpmReduction ~= nil
							or ( self.vehicle.mrGbMS.HydrostaticIncFactor >= 1 and self.vehicle.mrGbMS.HydrostaticDecFactor >= 1 )
							or self.lastRealMotorRpm > self.lastMaxPossibleRpm 
							or self.lastRealMotorRpm > m0
							or self.lastRealMotorRpm < n0 then
						self.hydrostaticFactorT = hTgt
					elseif math.abs( hTgt - self.hydrostaticFactorT ) > gearboxMogli.eps then
						if hTgt > self.hydrostaticFactorT then
							self.hydrostaticFactorT = self.hydrostaticFactorT + math.min( hTgt - self.hydrostaticFactorT,  self.tickDt * self.vehicle.mrGbMS.HydrostaticIncFactor ) 		
						else
							self.hydrostaticFactorT = self.hydrostaticFactorT + math.max( hTgt - self.hydrostaticFactorT, -self.tickDt * self.vehicle.mrGbMS.HydrostaticDecFactor )
						end
					end				
					
					if      self.hydrostaticFactorT > gearboxMogli.minHydrostaticFactor 
							and not ( self.vehicle.mrGbMS.HydrostaticDirect )
							and not ( self.ptoOn ) then
						self.targetRpm = Utils.clamp( w / self.hydrostaticFactorT, n1, m1 )
					end
					
					local hMin2 = Utils.clamp( wMin * r / self:getNextPossibleRpm( t + d, n0, m0 ), hMin, hMax )
					local hMax2 = Utils.clamp( wMax * r / self:getNextPossibleRpm( t - d, n0, m0 ), hMin, hMax )
					
					if hFix > 0 then
						hMin2 = math.min( hMin2, hFix )
						hMax2 = math.min( hMax2, hFix )
					end
					
					-- HydrostaticLossFxTorqueRatio
					-- HydrostaticLossFxRpmRatio 
					
					local hFx = 1
					if self.vehicle.mrGbMS.HydrostaticLossFxRpmRatio > 0 then
						local f 
						if     self.usedTransTorque <  gearboxMogli.eps then
							f = 0
						elseif self.usedTransTorque >= self.maxMotorTorque * self.vehicle.mrGbMS.HydrostaticLossFxTorqueRatio then
							f = 1
						else
							f = self.usedTransTorque / ( self.maxMotorTorque * self.vehicle.mrGbMS.HydrostaticLossFxTorqueRatio )
						end
						
					--local r = math.min( ( 1 + f * self.vehicle.mrGbMS.HydrostaticLossFxRpmRatio ) * t, math.max( t, self.maxMaxPowerRpm ) )
					--hFx = math.max( 0, self.hydrostaticFactorT - w / Utils.clamp( r, n1, m1 ) )
						hFx = 1 / ( 1 + f * self.vehicle.mrGbMS.HydrostaticLossFxRpmRatio )
						
						if self.vehicle.mrGbMG.debugInfo then
							self.vehicle.mrGbML.hydroTorqueFxInfo = string.format( "%5.3f, %4d => %4.2f", f, t, hFx )
						end
					end
					
					self.hydrostaticFactor = Utils.clamp( self.hydrostaticFactorT * hFx, hMin2, hMax2 )
					
					if gearboxMogli.debugGearShift then
						if self.hydrostaticFactor > gearboxMogli.eps then
							print(string.format("C: s: %6g w0: %6g w: %4d t: %4d h: %6g hT: %6g %6g..%6g %6g..%6g %6g..%6g",
																	self.vehicle.lastSpeedReal * 1000 * gearboxMogli.factor30pi * self.vehicle.movingDirection,
																	w0,
																	w,
																	w/self.hydrostaticFactor,
																	self.hydrostaticFactor,
																	self.hydrostaticFactorT,
																	hMin,hMax,hMin1,hMax1,hMin2,hMax2))
						else
							print(string.format("D")) 
						end
					end
				end
				
				self.vehicle.mrGbML.afterShiftRpm = nil
				
				-- launch & clutch					
				local r = gearboxMogli.gearSpeedToRatio( self.vehicle, self.vehicle.mrGbMS.CurrentGearSpeed )
				if     self.vehicle.mrGbMS.HydrostaticLaunch then
					clutchMode             = 0
					self.autoClutchPercent = self.vehicle.mrGbMS.MaxClutchPercent
				elseif self.hydrostaticFactor <= hMin then
					clutchMode             = 1
					self.hydrostaticFactor = hMin 
				elseif self.autoClutchPercent + gearboxMogli.eps < 1 then
					clutchMode             = 1
					self.hydrostaticFactor = math.max( self.hydrostaticFactor, r / gearboxMogli.maxManualGearRatio )
				elseif self.hydrostaticFactor < r / gearboxMogli.maxManualGearRatio then
					-- open clutch to stop
					clutchMode             = 1
					self.hydrostaticFactor = r / gearboxMogli.maxManualGearRatio
				else
					local smallestGearSpeed  = self.vehicle.mrGbMS.Gears[self.vehicle.mrGbMS.CurrentGear].speed 
																	 * self.vehicle.mrGbMS.Ranges[self.vehicle.mrGbMS.CurrentRange].ratio
																	 * self.vehicle.mrGbMS.Ranges2[self.vehicle.mrGbMS.CurrentRange2].ratio
																	 * self.vehicle.mrGbMS.GlobalRatioFactor
																	 * hMin
																	 * 3.6
					if self.vehicle.mrGbMS.ReverseActive then	
						smallestGearSpeed = smallestGearSpeed * self.vehicle.mrGbMS.ReverseRatio 
					end															 
					
					if currentAbsSpeed < smallestGearSpeed then
						clutchMode             = 1
					else
						clutchMode             = 0
						self.autoClutchPercent = self.vehicle.mrGbMS.MaxClutchPercent
						self.hydrostaticFactor = math.max( self.hydrostaticFactor, r / gearboxMogli.maxManualGearRatio )
					end			
				end			
				
				-- check static boundaries
				if     self.hydrostaticFactor > hMax then
					self.hydrostaticFactor = hMax
				elseif self.hydrostaticFactor < hMin then
					self.hydrostaticFactor = hMin
				end
				
	--**********************************************************************************************************		
	-- automatic shifting			
	--**********************************************************************************************************		
			elseif self.vehicle:mrGbMGetAutomatic() 
					and not ( self.vehicle.mrGbMS.AllAuto 
								and self.vehicle.mrGbMS.AllAutoMode      <= 0
								and self.vehicle.mrGbMS.AutoShiftRequest == 0 ) then
				local maxAutoRpm   = self.vehicle.mrGbMS.CurMaxRpm - math.min( 50, 0.5 * ( self.vehicle.mrGbMS.CurMaxRpm - self.vehicle.mrGbMS.RatedRpm ) )
				local halfOverheat = 0.5 * self.vehicle.mrGbMS.ClutchOverheatStartTime										
				local gearMaxSpeed = self.vehicle.mrGbMS.GlobalRatioFactor
				if self.vehicle.mrGbMS.ReverseActive then	
					gearMaxSpeed = gearMaxSpeed * self.vehicle.mrGbMS.ReverseRatio 
				end
				
				local possibleCombinations = {}
				local shiftRange1st        = false

				table.insert( possibleCombinations, { gear     = self.vehicle.mrGbMS.CurrentGear,
																							range1   = self.vehicle.mrGbMS.CurrentRange,
																							range2   = self.vehicle.mrGbMS.CurrentRange2,
																							priority = 0} )

				local alwaysShiftGears  =  self.vehicle.mrGbMS.GearTimeToShiftGear    < self.vehicle.mrGbMG.maxTimeToSkipGear 
																or self.vehicle.mrGbMS.ShiftNoThrottleGear
																or ( self.vehicle.mrGbMS.MatchGears ~= nil and self.vehicle.mrGbMS.MatchGears == "true" )
				local alwaysShiftRange  =  self.vehicle.mrGbMS.GearTimeToShiftHl      < self.vehicle.mrGbMG.maxTimeToSkipGear 
																or self.vehicle.mrGbMS.ShiftNoThrottleHl
																or ( self.vehicle.mrGbMS.MatchRanges ~= nil and self.vehicle.mrGbMS.MatchRanges == "true" )
				local alwaysShiftRange2 =  self.vehicle.mrGbMS.GearTimeToShiftRanges2 < self.vehicle.mrGbMG.maxTimeToSkipGear
																or self.vehicle.mrGbMS.ShiftNoThrottleRanges2
				
				local downRpm   = math.max( self.vehicle.mrGbMS.IdleRpm,  self.vehicle.mrGbMS.MinTargetRpm * gearboxMogli.rpmReduction )
				local upRpm     = math.max( self.vehicle.mrGbMS.RatedRpm, self.maxMaxPowerRpm )
							
				if self.vehicle.mrGbMS.AutoShiftDownRpm ~= nil and self.vehicle.mrGbMS.AutoShiftDownRpm > downRpm then
					downRpm = self.vehicle.mrGbMS.AutoShiftDownRpm
				end
				if self.vehicle.mrGbMS.AutoShiftUpRpm   ~= nil and self.vehicle.mrGbMS.AutoShiftUpRpm   < upRpm   then
					upRpm  = self.vehicle.mrGbMS.AutoShiftUpRpm
				end
				
			--if self.ptoOn then
			--	-- PTO => keep RPM
			--	local u = upRpm 
			--	upRpm   = Utils.clamp( self.minRequiredRpm + gearboxMogli.ptoRpmThrottleDiff, downRpm, upRpm )
			--	downRpm = Utils.clamp( minRpmReduced       - gearboxMogli.ptoRpmThrottleDiff, downRpm, u )
			--end
				
				local rpmC = self.absWheelSpeedRpmS * gearboxMogli.gearSpeedToRatio( self.vehicle, self.vehicle.mrGbMS.CurrentGearSpeed )
				if      accelerationPedal < -gearboxMogli.accDeadZone
						and self.vehicle.mrGbMS.CurrentGearSpeed > self.vehicle.mrGbMS.LaunchGearSpeed + gearboxMogli.eps then
					-- allow immediate down shift while braking
					downRpm = math.min( math.max( downRpm, self.targetRpm ), upRpm )
				end
				
				if self.vehicle.mrGbMS.TorqueConverter and downRpm <= self.vehicle.mrGbMS.ClutchMaxTargetRpm then
					downRpm = downRpm * self.vehicle.mrGbMS.MinClutchPercentTC 
				end
				
				local m2g = table.getn( self.vehicle.mrGbMS.Gears )
				local m2r = table.getn( self.vehicle.mrGbMS.Ranges )
				local m22 = table.getn( self.vehicle.mrGbMS.Ranges2 )
									
				local function loop( possibleCombinations, n0, n1, n2 )
					local tmp = {}
					for i,p in pairs( possibleCombinations ) do
						table.insert( tmp, p )
					end
					
					local function push( i0, i1, i2 ) 
						local p={} 
						p[n0]=i0
						p[n1]=i1 
						p[n2]=i2
						return p
					end
					
					local function pop( p ) 
						return p[n0], p[n1], p[n2]
					end
					
					local c0, c1, c2 = pop( { gear   = self.vehicle.mrGbMS.CurrentGear,
																		range1 = self.vehicle.mrGbMS.CurrentRange,
																		range2 = self.vehicle.mrGbMS.CurrentRange2 } )
					local a0, a1, a2 = pop( { gear   = alwaysShiftGears,
																		range1 = alwaysShiftRange,
																		range2 = alwaysShiftRange2 } )
					local r0, r1, r2 = pop( { gear   = self.vehicle.mrGbMS.Gears,
																		range1 = self.vehicle.mrGbMS.Ranges,
																		range2 = self.vehicle.mrGbMS.Ranges2 } )
					
					for _,p in pairs( possibleCombinations ) do					
						for i0,g in pairs(r0) do
							local _, i1, i2     = pop( p )
							local priority      = 0
							local fg, f1, f2
							local tg, t1, t2
							local skip = false
							
							do
								local f2g, t2g = 1, m2g
								local f2r, t2r = 1, m2r
								local f22, t22 = 1, m22
								local q = push( i0, i1, i2 )
								
								if q.range1 == nil or q.range1 < 1 or q.range1 > m2r then
									print(tostring(q))
									gearboxMogli.printCallStack()
								end
																
								f2r = math.max( f2r, Utils.getNoNil( self.vehicle.mrGbMS.Gears[q.gear].minRange, 1 ) )
								t2r = math.min( t2r, Utils.getNoNil( self.vehicle.mrGbMS.Gears[q.gear].maxRange, m2r ) )
								f22 = math.max( f22, Utils.getNoNil( self.vehicle.mrGbMS.Gears[q.gear].minRange2, 1 ) )
								t22 = math.min( t22, Utils.getNoNil( self.vehicle.mrGbMS.Gears[q.gear].maxRange2, m22 ) )
								f2g = math.max( f2g, Utils.getNoNil( self.vehicle.mrGbMS.Ranges[q.range1].minGear, 1 ) )
								t2g = math.min( t2g, Utils.getNoNil( self.vehicle.mrGbMS.Ranges[q.range1].maxGear, m2g ) )
								f22 = math.max( f2r, Utils.getNoNil( self.vehicle.mrGbMS.Ranges[q.range1].minRange2, 1 ) )
								t22 = math.min( t2r, Utils.getNoNil( self.vehicle.mrGbMS.Ranges[q.range1].maxRange2, m22 ) )
								f2g = math.max( f2g, Utils.getNoNil( self.vehicle.mrGbMS.Ranges2[q.range2].minGear, 1 ) )
								t2g = math.min( t2g, Utils.getNoNil( self.vehicle.mrGbMS.Ranges2[q.range2].maxGear, m2g ) )
								f2r = math.max( f2r, Utils.getNoNil( self.vehicle.mrGbMS.Ranges2[q.range2].minRange, 1 ) )
								t2r = math.min( t2r, Utils.getNoNil( self.vehicle.mrGbMS.Ranges2[q.range2].maxRange, m2r ) )

								fg, f1, f2 = pop( { gear=f2g, range1=f2r, range2=f22 } )
								tg, t1, t2 = pop( { gear=f2g, range1=f2r, range2=f22 } )
							end
							
							if self.vehicle.mrGbMS.ReverseActive  then
								if g.forwardOnly then
									skip = true
								end
							else
								if g.reverseOnly then
									skip = true
								end
							end
							
							if a0 or ( ( i1 == c1 or a1 ) and ( i2 == c2 or a2 ) ) then
								priority = 0
							else				
							--skip     = true
								priority = 10
							end
							
								-- keep the complete range!!!
							if     i0 > c0 then
								if     n0 == "gear" and n1 == "range1" then
									i1 = Utils.clamp( i1 + r0[c0].upRangeOffset,1, m2r )
								elseif n0 == "range1" and n1 == "gear" then
									i1 = Utils.clamp( i1 + r0[c0].upGearOffset, 1, m2g )
								end
							elseif i0 < c0 then
								if     n0 == "gear" and n1 == "range1" then
									i1 = Utils.clamp( i1 + r0[c0].downRangeOffset,1, m2r )
								elseif n0 == "range1" and n1 == "gear" then
									i1 = Utils.clamp( i1 + r0[c0].downGearOffset, 1, m2g )
								end
							end
							
							if not skip then
								if p.priority > priority then
									priority = p.priority
								end
								
								for _,q in pairs( tmp ) do
									local j0, j1, j2 = pop( q )
									if j0 == i0 and j1 == i1 and j2 == i2 then
										if q.priority > priority then
											q.priority = priority 
										end
										skip = true
										break 
									end
								end
								
								if not skip then
									local q = push( i0, i1, i2 )
									q.priority = priority
									table.insert( tmp, q )
								end
							end
						end
					end
					
					return tmp
				end
						
				-- loop over gears 
				if self.vehicle:mrGbMGetAutoShiftGears() then
					possibleCombinations = loop( possibleCombinations, "gear", "range1", "range2" )
				end
						
				-- loop over range1
				if self.vehicle:mrGbMGetAutoShiftRange() then
					possibleCombinations = loop( possibleCombinations, "range1", "gear", "range2" )
				end
								
				-- loop over range2
				if self.vehicle:mrGbMGetAutoShiftRange2() then
					possibleCombinations = loop( possibleCombinations, "range2", "gear", "range1" )
				end
				
				local minTimeToShift = math.huge
				local refSpeed = self.vehicle.mrGbMS.CurrentGearSpeed --math.max( self.vehicle.mrGbMS.LaunchGearSpeed, self.vehicle.mrGbMS.CurrentGearSpeed )
				
				do
					local tmp = {}
					for i,p in pairs( possibleCombinations ) do
						local i2g = p.gear
						local i2r = p.range1
						local i22 = p.range2
						if not ( gearboxMogli.mrGbMIsNotValidEntry( self.vehicle, self.vehicle.mrGbMS.Gears[i2g],   i2g, i2r, i22 )
									or gearboxMogli.mrGbMIsNotValidEntry( self.vehicle, self.vehicle.mrGbMS.Ranges[i2r],  i2g, i2r, i22 )
									or gearboxMogli.mrGbMIsNotValidEntry( self.vehicle, self.vehicle.mrGbMS.Ranges2[i22], i2g, i2r, i22 ) ) then
							p.gearSpeed = gearMaxSpeed * self.vehicle.mrGbMS.Gears[p.gear].speed 
																	* self.vehicle.mrGbMS.Ranges[p.range1].ratio
																	* self.vehicle.mrGbMS.Ranges2[p.range2].ratio
							p.isCurrent   = true
							p.timeToShiftMax = 0
							p.timeToShiftSum = 0
							
							if p.gear ~= self.vehicle.mrGbMS.CurrentGear then
								p.isCurrent      = false
								p.timeToShiftMax = math.max( p.timeToShiftMax, self.vehicle.mrGbMS.GearTimeToShiftGear )
								p.timeToShiftSum = p.timeToShiftSum + self.vehicle.mrGbMS.GearTimeToShiftGear
								p.priority       = math.max( p.priority, self.vehicle.mrGbMS.AutoShiftPriorityG )
							end
							if p.range1 ~= self.vehicle.mrGbMS.CurrentRange then
								p.isCurrent      = false
								p.timeToShiftMax = math.max( p.timeToShiftMax, self.vehicle.mrGbMS.GearTimeToShiftHl )
								p.timeToShiftSum = p.timeToShiftSum + self.vehicle.mrGbMS.GearTimeToShiftHl
								p.priority       = math.max( p.priority, self.vehicle.mrGbMS.AutoShiftPriorityR )
							end
							if p.range2 ~= self.vehicle.mrGbMS.CurrentRange2 then
								p.isCurrent      = false
								p.timeToShiftMax = math.max( p.timeToShiftMax, self.vehicle.mrGbMS.GearTimeToShiftRanges2 )
								p.timeToShiftSum = p.timeToShiftSum + self.vehicle.mrGbMS.GearTimeToShiftRanges2								
								p.priority       = math.max( p.priority, self.vehicle.mrGbMS.AutoShiftPriority2 )
							end
							
							if      p.priority == 1 
									and ( p.timeToShiftMax <= self.vehicle.mrGbMG.maxTimeToSkipGear 
										 or accelerationPedal < -gearboxMogli.accDeadZone
										 or ( accelerationPedal > 0.8 and self.deltaRpm < -gearboxMogli.autoShiftMaxDeltaRpm-gearboxMogli.autoShiftMaxDeltaRpm ) ) then
								p.priority = 0
							end
							
							p.plog = 0
							-- 0.6667 .. 1.3333 => 0
							-- < 0.5 or > 23    => 3
							if p.gearSpeed > self.vehicle.mrGbMS.CurrentGearSpeed then
							  p.plog   = math.min( math.max( 0, math.abs( math.log( p.gearSpeed / self.vehicle.mrGbMS.CurrentGearSpeed ) ) - 0.2877 ) * 7.4, 3 )
							end
							p.priority = p.priority + 0.1 * math.floor( p.plog * 3 )
							
							if not p.isCurrent and minTimeToShift > p.timeToShiftMax then
								minTimeToShift = p.timeToShiftMax
							end
							
							table.insert( tmp, p )
						end
					end
					possibleCombinations = tmp
				end
								
				local function sortGears( a, b )
					for _,comp in pairs( {"gearSpeed","timeToShiftMax","gear","range1","range2"} ) do
						if     a[comp] < b[comp] - gearboxMogli.eps then
							return true
						elseif a[comp] > b[comp] + gearboxMogli.eps then
							return false
						end
					end
					return false
				end
				table.sort( possibleCombinations, sortGears )
				
				local dumpIt = string.format("%4.2f ",self.vehicle.mrGbMS.CurrentGearSpeed)
				for i,p in pairs( possibleCombinations ) do
					dumpIt = dumpIt .. string.format("%2d: %4.2f %4.2f %4.2f ",i,p.gearSpeed,p.plog,p.priority)
				end
				
				local maxGear   = table.getn( possibleCombinations )
				local currentGearPower = self.absWheelSpeedRpmS * gearRatio
				
				if self.vehicle.mrGbMS.CurMinRpm < currentGearPower and currentGearPower < self.vehicle.mrGbMS.CurMaxRpm then
					currentGearPower = currentGearPower * self.currentTorqueCurve:get( currentGearPower )
				else
					currentGearPower = 0
				end

				local maxDcSpeed = math.huge
				
				if      self.vehicle.dCcheckModule ~= nil
						and self.vehicle:dCcheckModule("gasAndGearLimiter") 
						and self.vehicle.driveControl.gasGearLimiter.gearLimiter ~= nil 
						and self.vehicle.driveControl.gasGearLimiter.gearLimiter < 1.0 then				
					maxDcSpeed = self.vehicle.driveControl.gasGearLimiter.gearLimiter * possibleCombinations[maxGear][4]
				end

				local upTimerMode   = 1
				local downTimerMode = 1
				
				if      self.lastMotorRpm     > upRpm
						and self.lastRealMotorRpm > upRpm
						and self.clutchRpm        > upRpm then
					-- allow immediate up shift
					upTimerMode   = 0
				elseif  accelerationPedal                    < -gearboxMogli.accDeadZone
						and self.vehicle.mrGbMS.CurrentGearSpeed > self.vehicle.mrGbMS.LaunchGearSpeed + gearboxMogli.eps then
					-- allow immediate down shift while braking
					upTimerMode   = 2
					downTimerMode = 1
				elseif  self.clutchOverheatTimer ~= nil
						and self.clutchPercent       < 0.9 
						and self.clutchOverheatTimer > 0.5 * self.vehicle.mrGbMS.ClutchOverheatStartTime then
					downTimerMode = 0
				elseif  self.clutchRpm           < downRpm then
					-- allow down shift after short timeout
				--if self.vehicle.mrGbMS.CurrentGearSpeed > self.vehicle.mrGbMS.LaunchGearSpeed then
				--	downTimerMode = 0
				--end
				elseif  self.vehicle.cruiseControl.state > 0 
						and self.vehicle.mrGbMS.CurrentGearSpeed * downRpm / self.vehicle.mrGbMS.RatedRpm > currentSpeedLimit then
					-- allow down shift after short timeout
				elseif self.vehicle.mrGbML.lastGearSpeed < self.vehicle.mrGbMS.CurrentGearSpeed - gearboxMogli.eps then
					downTimerMode = 2
				elseif self.vehicle.mrGbML.lastGearSpeed > self.vehicle.mrGbMS.CurrentGearSpeed + gearboxMogli.eps then
					upTimerMode   = 2
				end		
				
				if     self.vehicle.mrGbMS.AutoShiftRequest > 0 then
					downTimerMode = 2
					upTimeMode    = 0
				elseif self.vehicle.mrGbMS.AutoShiftRequest < 0 then
					downTimerMode = 0
					upTimeMode    = 2
				end
				
				local sMin = nil
				local sMax = nil
				
				local bestScore = math.huge
				local bestGear  = -1
				local bestSpeed = gearboxMogli.eps
				
				local currScore = math.huge
				local currGear  = -1
				local currSpeed = gearboxMogli.eps
				
				local nextScore = math.huge
				local nextGear  = -1
				local nextSpeed = gearboxMogli.eps
				
				for i,p in pairs( possibleCombinations ) do
					p.score = math.huge
					p.rpmHi = self.absWheelSpeedRpmS * gearboxMogli.gearSpeedToRatio( self.vehicle, p.gearSpeed )
					p.rpmLo = p.rpmHi					
					--**********************************************************************************--
					-- estimate speed lost: 5.4 km/h lost at wheelLoad above 50 kNm for every 800 ms					
					if      p.timeToShiftMax    > 0 
							and accelerationPedal   > 0
							and p.gearSpeed         > 0 
							and self.maxMotorTorque > 0 
							and p.rpmHi            <= upRpm then
						-- rpmLo can become negative !!!
						p.rpmLo = p.rpmHi - p.timeToShiftMax * 0.00125 * Utils.clamp( self.wheelLoadS * 0.02, 0, 1 ) * self.vehicle.mrGbMS.RatedRpm / p.gearSpeed
						
						p.rpmLo = math.max( 0.5 * p.rpmHi, p.rpmLo )
					--if p.rpmHi >= downRpm and p.rpmLo < downRpm then p.rpmLo = downRpm end						
					end
					
					local isValidEntry = true
					
					if      downRpm                   <= rpmC and rpmC <= upRpm
							and p.rpmLo + gearboxMogli.eps < rpmC and rpmC < p.rpmHi - gearboxMogli.eps
							and p.timeToShiftMax           > self.vehicle.mrGbMG.maxTimeToSkipGear then
						-- the current gear is still valid => keep it
						p.priority = math.max( p.priority, 8 )
					elseif p.rpmHi < rpmC and rpmC < downRpm then
						-- the current gear is better than the new one
						p.priority = math.max( p.priority, 9 )
					elseif p.rpmHi > rpmC and rpmC > upRpm   then
						-- the current gear is better than the new one
						p.priority = math.max( p.priority, 9 )
					end

					if     self.vehicle.mrGbMS.AutoShiftRequest > 0 then
						if p.gearSpeed < self.vehicle.mrGbMS.CurrentGearSpeed + gearboxMogli.eps then
							isValidEntry = false 
						end
					elseif self.vehicle.mrGbMS.AutoShiftRequest < 0 then
						if p.gearSpeed > self.vehicle.mrGbMS.CurrentGearSpeed - gearboxMogli.eps then
							isValidEntry = false 
						end
					else
					
						if      self.vehicle.mrGbML.DirectionChangeTime ~= nil
								and g_currentMission.time  < self.vehicle.mrGbML.DirectionChangeTime + self.vehicle.mrGbMG.autoShiftTimeoutLong
								and p.gearSpeed            < self.vehicle.mrGbMS.LaunchGearSpeed - gearboxMogli.eps 
								and p.gearSpeed            < self.vehicle.mrGbMS.CurrentGearSpeed then
							isValidEntry = false
							dumpIt = dumpIt .. string.format("\n%d is not valid (a)",i)
						end
						
						-- no down shift if just idling  
						if      accelerationPedal      <  gearboxMogli.accDeadZone
								and downTimerMode          > 0
								and p.gearSpeed            < self.vehicle.mrGbMS.LaunchGearSpeed - gearboxMogli.eps 
								and p.gearSpeed            < self.vehicle.mrGbMS.CurrentGearSpeed
								and self.stallWarningTimer == nil 
								then
							isValidEntry = false
							dumpIt = dumpIt .. string.format("\n%d is not valid (b)",i)
						end
					end
						
					if p.gearSpeed < self.vehicle.mrGbMG.minAutoGearSpeed then
					--p.priority = 10
						isValidEntry = false
						dumpIt = dumpIt .. string.format("\n%d is not valid (c)",i)
					end
						
					if p.gearSpeed > maxDcSpeed then
						p.priority = 10
					end
					
					if      self.vehicle.cruiseControl.state > 0 
							and p.gearSpeed * self.vehicle.mrGbMS.IdleRpm > currentSpeedLimit * self.vehicle.mrGbMS.RatedRpm then
						p.priority = 10
					end			
					
					if      isValidEntry 
							and not p.isCurrent then
						if      self.deltaRpm < -gearboxMogli.autoShiftMaxDeltaRpm
								and p.gearSpeed   > self.vehicle.mrGbMS.CurrentGearSpeed + gearboxMogli.eps then
							isValidEntry = false
							dumpIt = dumpIt .. string.format("\n%d is not valid (d)",i)
						elseif  self.deltaRpm > gearboxMogli.autoShiftMaxDeltaRpm
								and p.gearSpeed   < self.vehicle.mrGbMS.CurrentGearSpeed - gearboxMogli.eps then
							isValidEntry = false
							dumpIt = dumpIt .. string.format("\n%d is not valid (e)",i)
						end
					end
					
					if      isValidEntry 
							and not p.isCurrent 
							and self.vehicle.mrGbMS.AutoShiftTimeoutLong > 0 then
							
						local autoShiftTimeout = 0
						if     p.gearSpeed < self.vehicle.mrGbMS.CurrentGearSpeed - gearboxMogli.eps then
							autoShiftTimeout = downTimerMode							
						elseif p.gearSpeed > self.vehicle.mrGbMS.CurrentGearSpeed + gearboxMogli.eps then
							autoShiftTimeout = upTimerMode
						else
							autoShiftTimeout = math.min( downTimerMode, upTimerMode )
						end
						
						if autoShiftTimeout > 0 or ( p.priority >= 2 and p.gearSpeed > self.vehicle.mrGbMS.CurrentGearSpeed + gearboxMogli.eps ) then
							if     autoShiftTimeout >= 2 then
								autoShiftTimeout = self.lastClutchClosedTime + self.vehicle.mrGbMS.AutoShiftTimeoutLong
							elseif p.priority >= 3 then
								autoShiftTimeout = self.lastClutchClosedTime + self.vehicle.mrGbMS.AutoShiftTimeoutShort * ( 3 + autoShiftTimeout )
							elseif p.priority >= 2 then
								autoShiftTimeout = self.lastClutchClosedTime + self.vehicle.mrGbMS.AutoShiftTimeoutShort * ( 2 + autoShiftTimeout )
							elseif p.priority >= 1 then
								autoShiftTimeout = self.lastClutchClosedTime + self.vehicle.mrGbMS.AutoShiftTimeoutShort * 2
							else
								autoShiftTimeout = self.lastClutchClosedTime + self.vehicle.mrGbMS.AutoShiftTimeoutShort 
							end
							if     autoShiftTimeout + minTimeToShift   > g_currentMission.time then
								isValidEntry = false
								dumpIt = dumpIt .. string.format("\n%d is not valid (f)",i)
							elseif autoShiftTimeout + p.timeToShiftSum > g_currentMission.time then
								p.priority = math.max( p.priority, 7 )
							end
						end
					end
					
					if isValidEntry or self.vehicle.mrGbMG.debugPrint or gearboxMogli.debugGearShift or self.vehicle.mrGbML.autoShiftInfoPrint then
            local testRpm
						
						testRpm = self:getRpmScore( p.rpmLo, downRpm, upRpm )
						if p.rpmHi > p.rpmLo then
							testRpm = math.max( testRpm, self:getRpmScore( p.rpmHi, downRpm, upRpm ) )
						end

						local testPwr = 0
						if accelerationPedal > 0 or self.ptoOn then
							local t2 = self.currentTorqueCurve:get( p.rpmLo ) * gearboxMogli.autoShiftPowerRatio
							
							local deltaRatio = 0.15
							if getMaxPower then
								deltaRatio = 0.03
							end
						
							testPwr = Utils.clamp( ( self.requestedPower - p.rpmLo * t2 ) / self.currentMaxPower - deltaRatio, 0, 1 )
						end
						
						if     testRpm > 0 then
						-- reach RPM window
							p.score = 3 + testRpm
						elseif testPwr > 0 then
						-- and optimize power afterwards
							p.score = 2 + testPwr
						elseif p.priority >= 2
								or ( p.priority >= 1 and p.gearSpeed < self.vehicle.mrGbMS.CurrentGearSpeed - gearboxMogli.eps ) then
						-- sort by priority 
							p.score = 1 + 0.1 * math.min( p.priority, 10 )
						elseif self.ptoOn then
						-- PTO => optimize target RPM
							p.score = math.abs( self.targetRpm - p.rpmHi ) / self.vehicle.mrGbMS.RatedRpm
						elseif accelerationPedal < -gearboxMogli.accDeadZone then
						-- braking
							p.score = math.abs( self.targetRpm - p.rpmHi ) / self.vehicle.mrGbMS.RatedRpm
						elseif accelerationPedal <  gearboxMogli.accDeadZone then
						-- no acceleration => no fuel => optimize target RPM
							p.score = 0.1 + 0.9 * math.abs( self.targetRpm - p.rpmHi ) / self.vehicle.mrGbMS.RatedRpm
							if p.isCurrent then
								p.score = 0
							end
						else
						-- optimize fuel usage ratio
							p.score = Utils.clamp( 0.001 * self.fuelCurve:get( p.rpmHi ), 0, 0.4 )
							if p.rpmLo < p.rpmHi then
								p.score = math.max( p.score, Utils.clamp( 0.001 * self.fuelCurve:get( p.rpmLo ), 0, 0.4 ) )
							end
						end
					end
					
					if isValidEntry then
						-- gear is possible 																			
						if     bestScore == nil
								or bestScore > p.score
								or ( math.abs( bestScore - p.score ) < 1e-4
								 and math.abs( self.vehicle.mrGbMS.CurrentGearSpeed - p.gearSpeed ) < math.abs( self.vehicle.mrGbMS.CurrentGearSpeed - bestSpeed ) )
								then
							bestScore = p.score
							bestGear  = i
							bestSpeed = p.gearSpeed
						end		
						
						if p.isCurrent then
							currScore = p.score
							currGear  = i
							currSpeed = p.gearSpeed
						else
							if     nextScore == nil
									or nextScore > p.score
									or ( math.abs( nextScore - p.score ) < 1e-4
									 and math.abs( self.vehicle.mrGbMS.CurrentGearSpeed - p.gearSpeed ) < math.abs( self.vehicle.mrGbMS.CurrentGearSpeed - nextSpeed ) )
									then
								nextScore = p.score
								nextGear  = i
								nextSpeed = p.gearSpeed
							end		
						end	
						
					end
				end
						
				self.vehicle.mrGbDump = dumpIt 
				
				local bestRpmLo, bestRpmHi = -1, -1
				if possibleCombinations[bestGear] ~= nil then
					p = possibleCombinations[bestGear]
					bestRpmLo = p.rpmLo
					bestRpmHi = p.rpmHi
				end
				local nextRpmLo, nextRpmHi = -1, -1
				if possibleCombinations[nextGear] ~= nil then
					p = possibleCombinations[nextGear]
					nextRpmLo = p.rpmLo
					nextRpmHi = p.rpmHi
				end
				
				self.vehicle.mrGbML.autoShiftInfo = string.format("%4d / %4d (%4g) / %4d..%4d %3d%% / %1d %1d\ncurrent: %6.3f %2d %5.2f\nbest: %6.3f %2d %5.2f %4d %4d\nnext: %6.3f %2d %5.2f %4d %4d",
																													rpmC,
																													self.lastRealMotorRpm,
																													self.deltaRpm,
																													downRpm,
																													upRpm,
																													accelerationPedal*100,
																													upTimerMode,
																													downTimerMode,
																													Utils.getNoNil( currScore, -1 ),
																													Utils.getNoNil( currGear,  -1 ),
																													Utils.getNoNil( currSpeed, -1 ),
																													Utils.getNoNil( bestScore, -1 ),
																													Utils.getNoNil( bestGear,  -1 ),
																													Utils.getNoNil( bestSpeed, -1 ),
																													Utils.getNoNil( bestRpmLo, -1 ),
																													Utils.getNoNil( bestRpmHi, -1 ),
																													Utils.getNoNil( nextScore, -1 ),
																													Utils.getNoNil( nextGear,  -1 ),
																													Utils.getNoNil( nextSpeed, -1 ),
																													Utils.getNoNil( nextRpmLo, -1 ),
																													Utils.getNoNil( nextRpmHi, -1 ) )
				
				local doit = self.vehicle.mrGbML.autoShiftInfoPrint
				
				if bestGear ~= nil and possibleCombinations[bestGear] ~= nil then
					local p = possibleCombinations[bestGear]
					if     p.gear   ~= self.vehicle.mrGbMS.CurrentGear 
							or p.range2 ~= self.vehicle.mrGbMS.CurrentRange2 
							or p.range1 ~= self.vehicle.mrGbMS.CurrentRange then
							
						if self.vehicle.mrGbMG.debugPrint or gearboxMogli.debugGearShift then doit = true end
						
						self.vehicle:mrGbMSetState( "CurrentGear",   p.gear ) 		
						self.vehicle:mrGbMSetState( "CurrentRange",  p.range1 ) 
						self.vehicle:mrGbMSetState( "CurrentRange2", p.range2 )
	
						clutchMode                           = 2
						self.vehicle.mrGbML.manualClutchTime = 0
					end
				end										
				
				if doit then
					self.vehicle.mrGbML.autoShiftInfoPrint = false
					for i,p in pairs(possibleCombinations) do
						print(string.format("%2d, %2d, %2d (%1d): %5.2f",p.gear,p.range1,p.range2,p.priority,p.gearSpeed*3.6)
																..", "..tostring(self.vehicle.mrGbMS.Ranges2[p.range2].name)
																..", "..tostring(self.vehicle.mrGbMS.Gears[p.gear].name)
																..", "..tostring(self.vehicle.mrGbMS.Ranges[p.range1].name)
																..", "..string.format("%4d (%4d)",p.rpmHi,p.rpmLo)
																..", "..tostring(p.isCurrent)
																.." => "..tostring(p.score))
					end
					print(self.vehicle.mrGbML.autoShiftInfo)
				end
				
			end
		end
	end
	
	--**********************************************************************************************************		
	-- clutch			
	
	local lastTCR = self.lastTorqueConverterRatio 
	local lastTCL = self.torqueConverterLockupMs
	self.lastTorqueConverterRatio = nil
	self.torqueConverterLockupMs  = nil
	
	if clutchMode > 0 and not ( self.noTransmission ) then
		if self.vehicle:mrGbMGetAutoClutch() or self.vehicle.mrGbMS.TorqueConverter then
			local openRpm   = self.vehicle.mrGbMS.OpenRpm  + self.vehicle.mrGbMS.ClutchRpmShift * math.max( 1.4*self.motorLoadS - 0.4, 0 )
			local closeRpm  = self.vehicle.mrGbMS.CloseRpm + self.vehicle.mrGbMS.ClutchRpmShift * math.max( 1.4*self.motorLoadS - 0.4, 0 ) 
			local targetRpm = self.targetRpm
			
			if     clutchMode > 1 then
				openRpm        = self.vehicle.mrGbMS.MaxTargetRpm 
				closeRpm       = self.vehicle.mrGbMS.MaxTargetRpm 
				if self.vehicle.mrGbML.afterShiftRpm ~= nil then
					targetRpm = math.max( self.minRequiredRpm, self.vehicle.mrGbML.afterShiftRpm )
				end
			elseif self.vehicle.mrGbMS.Hydrostatic then
				openRpm         = self.vehicle.mrGbMS.CurMaxRpm
				closeRpm        = math.min( self.vehicle.mrGbMS.CurMaxRpm, self.targetRpm + gearboxMogli.hydroEffDiff )
				if self.vehicle.mrGbMS.AutoShiftUpRpm ~= nil and closeRpm > self.vehicle.mrGbMS.AutoShiftUpRpm then
					closeRpm = self.vehicle.mrGbMS.AutoShiftUpRpm 
				end
				if closeRpm > self.vehicle.mrGbMS.HydrostaticMaxRpm then
					closeRpm = self.vehicle.mrGbMS.HydrostaticMaxRpm
				end		
			end
			
			if      self.vehicle.mrGbMS.TorqueConverter 
					and self.vehicle.mrGbMS.TorqueConverterLockupMs ~= nil 
					and ( getMaxPower or self.ptoOn ) then
				openRpm = math.max( openRpm, closeRpm )
			end
			
			local fromClutchPercent   = self.vehicle.mrGbMS.MinClutchPercent
			local toClutchPercent     = self.vehicle.mrGbMS.MaxClutchPercent

			if      clutchMode > 1 
					and self.vehicle.mrGbML.afterShiftClutch ~= nil
					and not ( self.vehicle.mrGbMS.TorqueConverter ) then
				if self.vehicle.mrGbML.afterShiftClutch < 0 then
					self.autoClutchPercent = self:getClutchPercent( targetRpm, openRpm, closeRpm, fromClutchPercent, self.autoClutchPercent, toClutchPercent )
				else
					self.autoClutchPercent = self.vehicle.mrGbML.afterShiftClutch
				end
			elseif  self.vehicle.mrGbMS.TorqueConverter
			    and self.vehicle.mrGbMS.TorqueConverterLockupMs ~= nil 
					and self.autoClutchPercent       >= self.vehicle.mrGbMS.MaxClutchPercent - gearboxMogli.eps
					and self.clutchRpm               >  closeRpm
					then
				-- timer for torque converter lockup clutch
				if lastTCL == nil then
					self.torqueConverterLockupMs = g_currentMission.time + self.vehicle.mrGbMS.TorqueConverterLockupMs
				else
					self.torqueConverterLockupMs = lastTCL 
					if lastTCL > g_currentMission.time and self.autoClutchPercent < 1 then
						local f = ( lastTCL - g_currentMission.time ) / self.vehicle.mrGbMS.TorqueConverterLockupMs
						self.autoClutchPercent = math.max( self.autoClutchPercent, 1 + f * ( self.vehicle.mrGbMS.MaxClutchPercent - 1 ) )			
					else
						self.autoClutchPercent = 1
					end
				end
			else
				self.autoClutchPercent = Utils.clamp( self.autoClutchPercent, 0, self.vehicle.mrGbMS.MaxClutchPercent )

				if self.vehicle.mrGbMS.TorqueConverter then				
					local d = self.tickDt / math.max( 10, self.vehicle.mrGbMS.TorqueConverterTime + self.motorLoadS * self.vehicle.mrGbMS.TorqueConverterTimeInc )
					if clutchMode > 1 or lastTCR == nil or self.vehicle.mrGbMS.ManualClutch < gearboxMogli.eps then
						self.lastTorqueConverterRatio = 0
						self.autoClutchPercent        = self.vehicle.mrGbMS.MinClutchPercentTC
					elseif self.motorLoad > 0.3 then
						self.lastTorqueConverterRatio = math.min( 1, lastTCR + d * ( self.motorLoad - 0.3 ) / 0.7 )
					elseif self.motorLoad < 0.3 then
						self.lastTorqueConverterRatio = math.max( 0, lastTCR - d * ( 0.3 - self.motorLoad ) / 0.3 )
					end
					
					if openRpm > minRpmReduced then
						openRpm  = self.vehicle.mrGbMS.MaxTargetRpm  + self.lastTorqueConverterRatio * ( minRpmReduced - self.vehicle.mrGbMS.MaxTargetRpm )
					end
					if closeRpm > self.minRequiredRpm then
						closeRpm = self.vehicle.mrGbMS.MaxTargetRpm + self.lastTorqueConverterRatio * ( self.minRequiredRpm - self.vehicle.mrGbMS.MaxTargetRpm )
					end
				end				
				
				if clutchMode <= 1 then
					if self.nonClampedMotorRpm > self.vehicle.mrGbMS.CurMinRpm and self.tickDt < self.vehicle.mrGbMS.ClutchTimeDec then
						fromClutchPercent = math.max( fromClutchPercent, self.autoClutchPercent - self.tickDt/self.vehicle.mrGbMS.ClutchTimeDec )
					end
					local timeInc = self.vehicle.mrGbMS.ClutchShiftTime
					if self.clutchRpm < closeRpm then
						timeInc = self.vehicle.mrGbMS.ClutchTimeInc
					end
					if self.tickDt < timeInc then
						toClutchPercent = math.min( toClutchPercent, self.autoClutchPercent + self.tickDt/timeInc )
					end
				end
				
				local c = self:getClutchPercent( targetRpm, openRpm, closeRpm, fromClutchPercent, self.autoClutchPercent, toClutchPercent )
								
				self.autoClutchPercent = c
			end
			
		else
			self.autoClutchPercent   = self.vehicle.mrGbMS.MaxClutchPercent
		end 		
	end 					
	
	local lastStallWarningTimer = self.stallWarningTimer
	self.stallWarningTimer = nil
	
	if     self.noTransmission then
		self.clutchPercent = 0
	elseif self.vehicle:mrGbMGetAutoClutch() or self.vehicle.mrGbMS.TorqueConverterOrHydro then
		self.clutchPercent = math.min( self.autoClutchPercent, self.vehicle.mrGbMS.ManualClutch )
		
		if not ( self.noTransmission ) and self.vehicle.mrGbML.debugTimer ~= nil and g_currentMission.time < self.vehicle.mrGbML.debugTimer and self.autoClutchPercent < self.vehicle.mrGbMS.MaxClutchPercent then
			self.vehicle.mrGbML.debugTimer = math.max( g_currentMission.time + 200, self.vehicle.mrGbML.debugTimer )
		end
	else
	--local minRpm = math.min( 100, 0.5 * self.vehicle.mrGbMS.CurMinRpm ) --math.max( 0.5 * self.vehicle.mrGbMS.CurMinRpm, self.vehicle.mrGbMS.CurMinRpm - 100 )
		local minRpm = math.max( 0.5 * self.vehicle.mrGbMS.CurMinRpm, self.vehicle.mrGbMS.CurMinRpm - 100 )
		if not ( self.noTransmission ) and self.vehicle.mrGbMS.ManualClutch > self.vehicle.mrGbMS.MinClutchPercent and self.nonClampedMotorRpm < minRpm then
			if lastStallWarningTimer == nil then
				self.stallWarningTimer = g_currentMission.time
			else
				self.stallWarningTimer = lastStallWarningTimer
				if     g_currentMission.time > self.stallWarningTimer + self.vehicle.mrGbMG.stallMotorOffTime then
					self.stallWarningTimer = nil
					self:motorStall( string.format("Motor stopped because RPM too low: %4.0f < %4.0f", self.nonClampedMotorRpm, minRpm ),
													 string.format("RPM is too low: %4.0f < %4.0f", self.nonClampedMotorRpm, minRpm ) )
				elseif g_currentMission.time > self.stallWarningTimer + self.vehicle.mrGbMG.stallWarningTime then
					self.vehicle:mrGbMSetState( "WarningText", string.format("RPM is too low: %4.0f < %4.0f", self.nonClampedMotorRpm, minRpm ))
				end		
			end		
		end
		
		self.clutchPercent = self.vehicle.mrGbMS.ManualClutch
	end
	
	
	--**********************************************************************************************************		
	-- no transmission => min throttle 
	if self.noTorque       then
		self.lastThrottle   = 0
		accelerationPedal   = 0
	end
	if self.clutchPercent < gearboxMogli.minClutchPercent then
		self.noTransmission = true
	end

	local it = self.vehicle.mrGbMS.IdleEnrichment + math.max( 0, handThrottle ) * ( 1 - self.vehicle.mrGbMS.IdleEnrichment )
	if     self.lastRealMotorRpm < self.minRequiredRpm - 1 then
		it = 0.5
	elseif self.lastRealMotorRpm > self.minRequiredRpm + 1 then
		it = 0
	end
	self.idleThrottle   = Utils.clamp( self.idleThrottle + Utils.clamp( it - self.idleThrottle, -maxDeltaThrottle, maxDeltaThrottle ), 0, 1 )
	
	if self.noTorque then
		self.lastThrottle = 0
	elseif self.vehicle:mrGbMGetOnlyHandThrottle() then
		self.lastThrottle = self.vehicle.mrGbMS.HandThrottle
	else
		self.lastThrottle = math.max( self.vehicle.mrGbMS.HandThrottle, accelerationPedal )
	end
	local f = 1
	if self.vehicle.mrGbML.gearShiftingNeeded > 0 then
		f = 2
	end

	if self.noTransmission then
		if self.lastThrottle > 0 and self.lastThrottle > ( self.lastMotorRpm / self.maxRpm )  then
			self.lastMotorRpm  = Utils.clamp( self.lastMotorRpm + f * self.lastThrottle * self.tickDt * self.vehicle.mrGbMS.RpmIncFactor, 
																			 self.minRequiredRpm, 
																			 self:getThrottleMaxRpm( ) )
		else
			self.lastMotorRpm  = Utils.clamp( self.lastMotorRpm - self.tickDt * self.vehicle.mrGbMS.RpmDecFactor, self.minRequiredRpm, self.vehicle.mrGbMS.CurMaxRpm )
		end	
		
		self.minThrottle    = self.idleThrottle
		self.lastThrottle   = math.max( self.minThrottle, self.lastThrottle )	
	end	
	
	--**********************************************************************************************************		
	-- timer for automatic shifting				
	if      self.noTransmission then
		self.lastClutchClosedTime = g_currentMission.time
		self.hydrostaticStartTime = nil
		self.deltaRpm             = 0
	elseif  self.lastClutchClosedTime            > g_currentMission.time 
			and self.clutchPercent                  >= self.vehicle.mrGbMS.MaxClutchPercent - gearboxMogli.eps then
		-- cluch closed => "start" the timer
		self.lastClutchClosedTime = g_currentMission.time 
	elseif  math.abs( accelerationPedal )        < gearboxMogli.accDeadZone
			and self.vehicle.mrGbMS.CurrentGearSpeed < self.vehicle.mrGbMS.LaunchGearSpeed + gearboxMogli.eps 
			and ( self.clutchPercent                >= self.vehicle.mrGbMS.MaxClutchPercent - gearboxMogli.eps
			   or self.vehicle.mrGbMS.TorqueConverter )
			and self.lastClutchClosedTime            < g_currentMission.time 
			and self.vehicle.steeringEnabled
			then
		-- no down shift for small gears w/o throttle
		self.lastClutchClosedTime = g_currentMission.time 
	end
	
	
	--**********************************************************************************************************		
	-- overheating of clutch				
	if self.vehicle.mrGbMS.ClutchCanOverheat and not ( self.vehicle:getIsHired() ) then
		if 0.1 < self.clutchPercent and self.clutchPercent < 0.9 then
			if self.clutchOverheatTimer == nil then
				self.clutchOverheatTimer = 0
			else
				self.clutchOverheatTimer = self.clutchOverheatTimer + self.tickDt * self.motorLoadP * Utils.clamp( 1 - self:getGearRatioFactor(), 0, 1 )
			end

			if self.vehicle.mrGbMS.ClutchOverheatMaxTime > 0 then
				self.clutchOverheatTimer = math.min( self.clutchOverheatTimer, self.vehicle.mrGbMS.ClutchOverheatMaxTime )
			end
			
			if self.clutchOverheatTimer > self.vehicle.mrGbMS.ClutchOverheatStartTime then
				local w = "Clutch is overheating"
				if      self.vehicle.mrGbMS.WarningText ~= nil
						and self.vehicle.mrGbMS.WarningText ~= "" 
						and self.vehicle.mrGbMS.WarningText ~= w 
						and string.len( self.vehicle.mrGbMS.WarningText ) < 200 then
					w = self.vehicle.mrGbMS.WarningText .. " / " .. w
				end
					
				self.vehicle:mrGbMSetState( "WarningText", w )
				
				if self.vehicle.mrGbMS.ClutchOverheatIncTime > 0 then
					local e = 1 + ( self.clutchOverheatTimer - self.vehicle.mrGbMS.ClutchOverheatStartTime ) / self.vehicle.mrGbMS.ClutchOverheatIncTime
					self.clutchPercent = self.clutchPercent ^ e
				end
			end
		elseif self.clutchOverheatTimer ~= nil then
			self.clutchOverheatTimer = self.clutchOverheatTimer - self.tickDt
			
			if self.clutchOverheatTimer < 0 then
				self.clutchOverheatTimer = nil
			end
		end
	elseif self.clutchOverheatTimer ~= nil then 
		self.clutchOverheatTimer = nil
	end

	--**********************************************************************************************************		
	-- calculate max RPM increase based on current RPM
	if self.noTransmission then
		self.maxPossibleRpm = gearboxMogli.huge
		self.lastMaxRpmTab  = nil
		self.rpmIncFactor   = self.vehicle.mrGbMS.RpmIncFactor
	elseif self.lastMissingTorque > 0 then
		self.maxPossibleRpm = self.vehicle.mrGbMS.CurMaxRpm
		self.lastMaxRpmTab  = nil
		self.rpmIncFactor   = self.vehicle.mrGbMS.RpmIncFactorFull
	else
		local tab = nil
		if self.lastMaxRpmTab == nil then
		--tab = nil
		elseif lastNoTransmission then
		--tab = nil
		else
			tab = self.lastMaxRpmTab
		end
		
		local m 
		if type( self.lastRealMotorRpm ) == "number" then
			m = self.lastRealMotorRpm
		else
			print( 'ERROR in gearboxMogli.lua(7838): type( self.lastRealMotorRpm ) ~= "number"' )
			m = self.nonClampedMotorRpm
		end
		if m < self.vehicle.mrGbMS.IdleRpm then
			m = self.vehicle.mrGbMS.IdleRpm
		end
		
		self.lastMaxRpmTab = {}
		table.insert( self.lastMaxRpmTab, { t = 0, m = m } )
				
		if tab ~= nil then
			local mm = m
			local cm = 1
			
			for _,tm in pairs( tab ) do
				local t = tm.t + self.tickDt 
				if t < gearboxMogli.deltaLimitTimeMs then
					table.insert( self.lastMaxRpmTab, { t = t, m = tm.m } )
					mm = mm + tm.m + t * self.rpmIncFactor
					cm = cm + 1
				end
			end
			
			if cm > 1 then
				m = math.max( m, mm / cm )
			end
		end
		
		self.maxPossibleRpm = m + self.maxRpmIncrease
		if self.maxPossibleRpm < self.clutchRpm then
			self.maxPossibleRpm = self.clutchRpm
		end
		if self.maxPossibleRpm < minRpmReduced then
			self.maxPossibleRpm = minRpmReduced
		end
		if self.maxPossibleRpm > self.vehicle.mrGbMS.CurMaxRpm then
			self.maxPossibleRpm = self.vehicle.mrGbMS.CurMaxRpm
		end
		if      self.vehicle.mrGbMS.Hydrostatic
				and self.maxPossibleRpm > self.vehicle.mrGbMS.HydrostaticMaxRpm then
			self.maxPossibleRpm = self.vehicle.mrGbMS.HydrostaticMaxRpm
		end
		
		if self.vehicle.mrGbML.afterShiftRpm ~= nil then -- and self.vehicle.mrGbML.gearShiftingEffect then
			if self.maxPossibleRpm > self.vehicle.mrGbML.afterShiftRpm then
				self.maxPossibleRpm               = self.vehicle.mrGbML.afterShiftRpm
				self.vehicle.mrGbML.afterShiftRpm = self.vehicle.mrGbML.afterShiftRpm + self.maxRpmIncrease 
			else
				self.vehicle.mrGbML.afterShiftRpm = nil
			end
		end
	end
	
	if self.vehicle.mrGbML.afterShiftRpm ~= nil and self.vehicle.mrGbML.gearShiftingEffect and not self.noTransmission then 
		self.lastMotorRpm = self.vehicle.mrGbML.afterShiftRpm
		self.vehicle.mrGbML.gearShiftingEffect = false
	end
	
	--**********************************************************************************************************		
	-- do not cut torque in case of open clutch or torque converter
	if self.clutchPercent < 1 and self.maxPossibleRpm < self.vehicle.mrGbMS.CloseRpm then
		self.maxPossibleRpm = self.vehicle.mrGbMS.CloseRpm
	end	
	
	--**********************************************************************************************************		
	-- reduce RPM if more power than available is requested 
	local reductionMinRpm = self.vehicle.mrGbMS.CurMinRpm 
	if     currentAbsSpeed < 1 then
		reductionMinRpm = self.vehicle.mrGbMS.CurMaxRpm 
	elseif currentAbsSpeed < 2 then
		reductionMinRpm = self.vehicle.mrGbMS.CurMaxRpm + ( currentAbsSpeed - 1 ) * ( self.vehicle.mrGbMS.CurMinRpm - self.vehicle.mrGbMS.CurMaxRpm )
	end
	if self.vehicle.mrGbMS.IsCombine and reductionMinRpm < self.vehicle.mrGbMS.ThreshingMinRpm then
		reductionMinRpm = self.vehicle.mrGbMS.ThreshingMinRpm
	end
	
	if      self.lastMissingTorque  > 0 
			and self.nonClampedMotorRpm > reductionMinRpm
			and not ( self.noTransmission ) then
		if self.torqueRpmReduction == nil then
			self.torqueRpmReference = self.nonClampedMotorRpm
			self.torqueRpmReduction = 0
		end
		local m = self.vehicle.mrGbMS.CurMinRpm
		self.torqueRpmReduction   = math.min( self.nonClampedMotorRpm - reductionMinRpm, self.torqueRpmReduction + math.min( 0.2, self.lastMissingTorque / self.lastMotorTorque ) * self.tickDt * self.vehicle.mrGbMS.RpmDecFactor )
	elseif  self.torqueRpmReduction ~= nil then
		self.torqueRpmReduction = self.torqueRpmReduction - self.tickDt * self.rpmIncFactor 
		if self.torqueRpmReduction < 0 then
			self.torqueRpmReference = nil
			self.torqueRpmReduction = nil
		end
	end
	if self.torqueRpmReduction ~= nil and not self.vehicle.mrGbMS.Hydrostatic then
		self.maxPossibleRpm = Utils.clamp( self.torqueRpmReference - self.torqueRpmReduction, self.vehicle.mrGbMS.CurMinRpm, self.maxPossibleRpm )
	end
	
	self.lastThrottle = math.max( self.minThrottle, accelerationPedal )
	
--**********************************************************************************************************	
-- VehicleMotor.updateGear II
	self.gear, self.gearRatio = self.getBestGear(self, acceleration, self.wheelSpeedRpm, self.vehicle.mrGbMS.CurMaxRpm*0.1, requiredWheelTorque, self.minRequiredRpm )
--**********************************************************************************************************	
end

--**********************************************************************************************************	
-- gearboxMogliMotor:getMotorRpm
--**********************************************************************************************************	
function gearboxMogliMotor:getMotorRpm( cIn )
	if self.noTransmission then
		return self:getThrottleRpm()
	end
	if cIn == nil and self.clutchPercent > 0.999 then
		return self.clutchRpm
	end
	local c = self.clutchPercent
	if type( cIn ) == "number" then
		c = cIn
	end
	return c * self.clutchRpm + ( 1-c ) * self:getThrottleRpm()
end

--**********************************************************************************************************	
-- gearboxMogliMotor:getThrottleRpm
--**********************************************************************************************************	
function gearboxMogliMotor:getThrottleRpm( )
	return math.max( self.minRequiredRpm, self.vehicle.mrGbMS.IdleRpm + self.lastThrottle * ( self.vehicle.mrGbMS.CurMaxRpm - self.vehicle.mrGbMS.IdleRpm ) )
end

--**********************************************************************************************************	
-- gearboxMogliMotor:getThrottleRpm
--**********************************************************************************************************	
function gearboxMogliMotor:getThrottleMaxRpm( acc )
	if     acc == nil then 
		acc = self.lastThrottle 
	elseif acc > 1 then
		acc = 1
	elseif acc < 0 then
		acc = 0
	end
	return math.max( self.minRequiredRpm, self.vehicle.mrGbMS.IdleRpm + acc * math.max( 0, self.vehicle.mrGbMS.MaxTargetRpm - self.vehicle.mrGbMS.IdleRpm ) )
end

--**********************************************************************************************************	
-- gearboxMogliMotor:getNextPossibleRpm
--**********************************************************************************************************	
function gearboxMogliMotor:getNextPossibleRpm( rpm, lowerRpm, upperRpm )
	local curRpm = self.lastRealMotorRpm
	if self.lastMaxPossibleRpm ~= nil and self.lastMaxPossibleRpm < self.lastRealMotorRpm then
		curRpm     = self.lastMaxPossibleRpm
	end
	
	local l = Utils.getNoNil( lowerRpm, self.vehicle.mrGbMS.CurMinRpm )
	local u = Utils.getNoNil( upperRpm, self.vehicle.mrGbMS.CurMaxRpm )
	local minRpm = Utils.clamp( curRpm - self.tickDt * self.vehicle.mrGbMS.RpmDecFactor, l, u )
	local maxRpm = Utils.clamp( curRpm + self.tickDt * self.rpmIncFactor,                l, u )
	
	if     rpm < minRpm then
		return minRpm
	elseif rpm > maxRpm then
		return maxRpm
	end
	
	return rpm
end

--**********************************************************************************************************	
-- gearboxMogliMotor:getClutchPercent
--**********************************************************************************************************	
function gearboxMogliMotor:getClutchPercent( targetRpm, openRpm, closeRpm, fromPercent, curPercent, toPercent )

	local throttle = self:getThrottleRpm()
	
	if self.lastRealMotorRpm < openRpm and self.vehicle.mrGbMS.CurMinRpm < openRpm then
		local d1 = openRpm - throttle
		local d2 = math.abs( self.vehicle.lastSpeed*1000 ) * self.vehicle.mrGbMS.RatedRpm / self.vehicle.mrGbMS.CurrentGearSpeed - throttle
		if d2 > d1 and d1 > gearboxMogli.eps then
			return math.min( fromPercent, d1/d2 )
		end
	end
	if fromPercent ~= nil and toPercent ~= nil and fromPercent >= toPercent then
		return fromPercent
	end
--if closeRpm <= self.clutchRpm and self.clutchRpm <= self.vehicle.mrGbMS.CurMaxRpm then
	if closeRpm <= self.lastRealMotorRpm and self.lastRealMotorRpm <= self.vehicle.mrGbMS.CurMaxRpm then
		return Utils.getNoNil( toPercent, self.vehicle.mrGbMS.MaxClutchPercent )
	end
	if self.lastRealMotorRpm < self.vehicle.mrGbMS.CurMinRpm and self.vehicle.mrGbMS.CurMinRpm < openRpm then
		return Utils.getNoNil( fromPercent, self.vehicle.mrGbMS.MinClutchPercent )
	end	
	
	local minPercent = self.vehicle.mrGbMS.MinClutchPercent + Utils.clamp( 0.5 + 0.02 * ( self.lastRealMotorRpm - openRpm ), 0, 1 ) * math.max( 0, curPercent - self.vehicle.mrGbMS.MinClutchPercent )
	local maxPercent = self.vehicle.mrGbMS.MaxClutchPercent

	if fromPercent ~= nil and minPercent < fromPercent then
		minPercent = fromPercent
	end
	if toPercent   ~= nil and maxPercent > toPercent   then
		maxPercent = toPercent 
	end
	
	if minPercent + gearboxMogli.eps > maxPercent then
		return minPercent 
	end
	
	local target        = math.min( targetRpm, self.vehicle.mrGbMS.ClutchMaxTargetRpm )
	
	local eps           = maxPercent - minPercent
	local delta         = ( throttle - math.max( self.clutchRpm, 0 ) ) * eps
	
	local times         = math.max( gearboxMogli.clutchLoopTimes, math.ceil( delta / gearboxMogli.clutchLoopDelta ) )
	delta = delta / times 
	eps   = eps   / times 
	
	local clutchRpm     = maxPercent * math.max( self.clutchRpm, 0 ) + ( 1 - maxPercent ) * throttle
	local clutchPercent = maxPercent
	local diff, diffi, rpm
	
	for i=0,times do
		clutchRpm = clutchRpm + delta
		diffi     = math.abs( target - clutchRpm )
		if diff == nil or diff > diffi then
			diff = diffi
			clutchPercent = maxPercent - i * eps
		end
	end
	
	if      self.vehicle.mrGbMG.debugInfo 
			and self.autoClutchPercent < self.vehicle.mrGbMS.MaxClutchPercent
			and fromPercent ~= nil
			and toPercent   ~= nil then
		self.vehicle.mrGbML.clutchInfo = 
					string.format("Clutch: cur: %4.0f tar: %4.0f opn: %4.0f cls: %4.0f rg: %1.3f .. %1.3f => tar: %4.0f thr: %4.0f whl: %4.0f => mo %4.0f clu %4.0f diffi %4.0f => %1.3f (%4.4f %4.4f)",
												self.lastRealMotorRpm, targetRpm, openRpm, closeRpm,
												fromPercent, toPercent,
												target, throttle, self.clutchRpm, self:getMotorRpm(),
												clutchRpm, diff, clutchPercent, eps, delta )
	end 
	
	return clutchPercent 
end

--**********************************************************************************************************	
-- gearboxMogliMotor:getRpmScore
--**********************************************************************************************************	
function gearboxMogliMotor:getRpmScore( rpm, downRpm, upRpm ) 

	local f = downRpm-1000
	local t = upRpm  +1000

	if downRpm <= rpm and rpm <= upRpm then
		return 0
	elseif rpm <= f
	    or rpm >= t then
		return 1
	elseif rpm < downRpm then
		return ( downRpm - rpm ) * 0.001
	elseif rpm > upRpm then
		return ( rpm - upRpm ) * 0.001
	end
	-- error
	print("warning: invalid parameters in gearboxMogliMotor:getRpmScore( "..tostring(rpm)..", "..tostring(downRpm)..", "..tostring(upRpm).." )")
	return 1
end

--**********************************************************************************************************	
-- gearboxMogliMotor:splitGear
--**********************************************************************************************************	
function gearboxMogliMotor:splitGear( i ) 
	local i2g, i2r = 1, 1
	if     not self.vehicle:mrGbMGetAutoShiftRange() then
		i2g = i
		i2r = self.vehicle.mrGbMS.CurrentRange
	elseif not self.vehicle:mrGbMGetAutoShiftGears() then 
		i2g = self.vehicle.mrGbMS.CurrentGear
		i2r = i
	elseif self.vehicle.mrGbMS.GearTimeToShiftGear > self.vehicle.mrGbMS.GearTimeToShiftHl + 10 then
		-- shifting gears is more expensive => avoid paradox up/down shifts
		i2g = 1
		i2r = i
		local m = table.getn( self.vehicle.mrGbMS.Ranges )
		while i2r > m do
			i2g = i2g + 1
			i2r = i2r - m
		end		
	else
		i2r = 1
		i2g = i
		local m = table.getn( self.vehicle.mrGbMS.Gears )
		while i2g > m do
			i2r = i2r + 1
			i2g = i2g - m
		end
	end
	if i ~= self:combineGear( i2g, i2r ) then
		print("ERROR in GEARBOX: "..tostring(i).." ~= combine( "..tostring(i2r)..", "..tostring(i2g).." )")
	end
	return i2g,i2r
end

--**********************************************************************************************************	
-- gearboxMogliMotor:combineGear
--**********************************************************************************************************	
function gearboxMogliMotor:combineGear( I2g, I2r ) 
	local i2g = Utils.getNoNil( I2g, self.vehicle.mrGbMS.CurrentGear )
	local i2r = Utils.getNoNil( I2r, self.vehicle.mrGbMS.CurrentRange )
	
	if     not self.vehicle:mrGbMGetAutoShiftRange() then
		return i2g
	elseif not self.vehicle:mrGbMGetAutoShiftGears() then 
		return i2r
	elseif self.vehicle.mrGbMS.GearTimeToShiftGear > self.vehicle.mrGbMS.GearTimeToShiftHl + 10 then
		-- shifting gears is more expensive => avoid paradox up/down shifts
		local m = table.getn( self.vehicle.mrGbMS.Ranges )
		return i2r + m * ( i2g-1 )
	else
		local m = table.getn( self.vehicle.mrGbMS.Gears )
		return i2g + m * ( i2r-1 )
	end
	return 1
end

--**********************************************************************************************************	
-- gearboxMogliMotor:getRotInertia
--**********************************************************************************************************	
function gearboxMogliMotor:getRotInertia()
	local f = 1
	if self.noTransmission and ( self.vehicle.mrGbMG.reduceMOILowRatio or not ( self.vehicle.mrGbMS.HydrostaticLaunch ) ) then
		f = 0
	else
		if      self.vehicle.mrGbMG.reduceMOILowRatio 
				and self.ratioFactorR ~= nil 
				and self.ratioFactorR  > 1 then
			f = math.min( f, 1 / self.ratioFactorR )
		end
		if      self.vehicle.mrGbMG.reduceMOIClutchLimit ~= nil 
				and self.vehicle.mrGbMG.reduceMOIClutchLimit > 0.01
				and not ( self.vehicle.mrGbMS.HydrostaticLaunch ) 
				and self.clutchPercent < self.vehicle.mrGbMG.reduceMOIClutchLimit - gearboxMogli.eps then
			if self.vehicle.mrGbMG.reduceMOIClutchLimit >= 1 then
				f = math.min( f, self.clutchPercent )
			else
				f = math.min( f, self.clutchPercent / self.vehicle.mrGbMG.reduceMOIClutchLimit )
			end
		end
		if      self.vehicle.mrGbMG.reduceMOILowSpeed 
				and -0.0015 < self.vehicle.lastSpeedReal and self.vehicle.lastSpeedReal < 0.0015 then
			f = math.min( f, 0.250 + 500 * math.abs( self.vehicle.lastSpeedReal ) )
		end
	end
	self.vehicle.mrGbML.momentOfInertia = math.max( self.vehicle.mrGbMG.momentOfInertiaMin, 0.001 * f * self.vehicle.mrGbMS.MomentOfInertia )
	return self.vehicle.mrGbML.momentOfInertia
end

--**********************************************************************************************************	
-- gearboxMogliMotor:getDampingRate
--**********************************************************************************************************	
function gearboxMogliMotor:getDampingRate()
	local r = self.vehicle.mrGbMG.inertiaToDampingRatio * self:getRotInertia()
	return r
end

--**********************************************************************************************************	
-- gearboxMogliMotor:getMaximumForwardSpeed
--**********************************************************************************************************	
function gearboxMogliMotor:getMaximumForwardSpeed()
	local m = self.vehicle.mrGbMS.CurrentGearSpeed
	if self.vehicle.mrGbMS.Hydrostatic then
		m = self.vehicle.mrGbMS.HydrostaticMax * m
	end
	
	if m < self.original.maxForwardSpeed then
		m = 0.5 * m + 0.5 * self.original.maxForwardSpeed
	end
	
	return m             
end

--**********************************************************************************************************	
-- gearboxMogliMotor:getMaximumBackwardSpeed
--**********************************************************************************************************	
function gearboxMogliMotor:getMaximumBackwardSpeed()
	local m = self.vehicle.mrGbMS.CurrentGearSpeed
	if self.vehicle.mrGbMS.Hydrostatic then
		if self.vehicle.mrGbMS.HydrostaticMin < 0 then
			m = -self.vehicle.mrGbMS.HydrostaticMin * m
		else
			m = self.vehicle.mrGbMS.HydrostaticMax * m
		end
	end
	
	if m < self.original.maxBackwardSpeed then
		m = 0.5 * m + 0.5 * self.original.maxBackwardSpeed
	end
	
	return m	
end

end