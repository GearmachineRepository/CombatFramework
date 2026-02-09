--!strict

local RateLimiter = {}

export type Config = {
	MaxTokens: number,
	RefillRate: number,
	RefillInterval: number?,
}

export type Bucket = {
	Tokens: number,
	LastRefill: number,
}

export type RateLimiterInstance = {
	Check: (Key: string) -> boolean,
	Consume: (Key: string, Amount: number?) -> boolean,
	Reset: (Key: string) -> (),
	Cleanup: (MaxAge: number?) -> (),
	Destroy: () -> (),
}

function RateLimiter.Create(LimiterConfig: Config): RateLimiterInstance
	local MaxTokens = LimiterConfig.MaxTokens
	local RefillRate = LimiterConfig.RefillRate
	local RefillInterval = LimiterConfig.RefillInterval or 1
	local Buckets: { [string]: Bucket } = {}

	local function Refill(BucketData: Bucket)
		local Now = os.clock()
		local Elapsed = Now - BucketData.LastRefill
		local Intervals = math.floor(Elapsed / RefillInterval)

		if Intervals > 0 then
			BucketData.Tokens = math.min(MaxTokens, BucketData.Tokens + (Intervals * RefillRate))
			BucketData.LastRefill = BucketData.LastRefill + (Intervals * RefillInterval)
		end
	end

	local function GetOrCreateBucket(Key: string): Bucket
		local BucketData = Buckets[Key]
		if not BucketData then
			BucketData = {
				Tokens = MaxTokens,
				LastRefill = os.clock(),
			}
			Buckets[Key] = BucketData
		end
		return BucketData
	end

	local function Check(Key: string): boolean
		local BucketData = GetOrCreateBucket(Key)
		Refill(BucketData)
		return BucketData.Tokens >= 1
	end

	local function Consume(Key: string, Amount: number?): boolean
		local Cost = Amount or 1
		local BucketData = GetOrCreateBucket(Key)
		Refill(BucketData)

		if BucketData.Tokens < Cost then
			return false
		end

		BucketData.Tokens = BucketData.Tokens - Cost
		return true
	end

	local function Reset(Key: string)
		Buckets[Key] = nil
	end

	local function Cleanup(MaxAge: number?)
		local StaleThreshold = MaxAge or 60
		local Now = os.clock()

		for Key, BucketData in Buckets do
			if (Now - BucketData.LastRefill) > StaleThreshold then
				Buckets[Key] = nil
			end
		end
	end

	local function Destroy()
		table.clear(Buckets)
	end

	return {
		Check = Check,
		Consume = Consume,
		Reset = Reset,
		Cleanup = Cleanup,
		Destroy = Destroy,
	}
end

return RateLimiter