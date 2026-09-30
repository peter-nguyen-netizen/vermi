import Foundation

/// A Redis command's name, argument syntax and a one-line summary — used to
/// power command-name suggestions and the argument-syntax hint in the Console.
struct RedisCommandInfo: Identifiable {
    var id: String { name }
    let name: String
    let syntax: String
    let summary: String
}

enum RedisCommandCatalog {
    /// Full core Redis command set (server 7.x) plus RedisJSON. Grouped for
    /// readability; suggestion/lookup is name-based and case-insensitive.
    static let all: [RedisCommandInfo] = [
        // MARK: Connection
        .init(name: "AUTH", syntax: "AUTH [username] password", summary: "Authenticate to the server"),
        .init(name: "HELLO", syntax: "HELLO [protover [AUTH user pass] [SETNAME name]]", summary: "Handshake / switch RESP protocol"),
        .init(name: "PING", syntax: "PING [message]", summary: "Ping the server"),
        .init(name: "ECHO", syntax: "ECHO message", summary: "Echo the given string"),
        .init(name: "SELECT", syntax: "SELECT index", summary: "Change the selected database"),
        .init(name: "SWAPDB", syntax: "SWAPDB index1 index2", summary: "Swap two databases"),
        .init(name: "QUIT", syntax: "QUIT", summary: "Close the connection"),
        .init(name: "RESET", syntax: "RESET", summary: "Reset the connection state"),

        // MARK: Server / admin
        .init(name: "INFO", syntax: "INFO [section]", summary: "Server info and statistics"),
        .init(name: "DBSIZE", syntax: "DBSIZE", summary: "Number of keys in the DB"),
        .init(name: "FLUSHDB", syntax: "FLUSHDB [ASYNC|SYNC]", summary: "Remove all keys from the current DB"),
        .init(name: "FLUSHALL", syntax: "FLUSHALL [ASYNC|SYNC]", summary: "Remove all keys from all DBs"),
        .init(name: "CONFIG", syntax: "CONFIG GET|SET|RESETSTAT|REWRITE ...", summary: "Get/set configuration"),
        .init(name: "CLIENT", syntax: "CLIENT subcommand ...", summary: "Client connection management"),
        .init(name: "COMMAND", syntax: "COMMAND [COUNT|DOCS|INFO|LIST|GETKEYS ...]", summary: "Command metadata"),
        .init(name: "CLUSTER", syntax: "CLUSTER subcommand ...", summary: "Cluster management"),
        .init(name: "MEMORY", syntax: "MEMORY USAGE|DOCTOR|STATS|PURGE ...", summary: "Memory introspection"),
        .init(name: "SLOWLOG", syntax: "SLOWLOG GET|LEN|RESET", summary: "Slow query log"),
        .init(name: "LATENCY", syntax: "LATENCY HISTORY|LATEST|RESET|DOCTOR|GRAPH", summary: "Latency monitoring"),
        .init(name: "ACL", syntax: "ACL subcommand ...", summary: "Access control lists"),
        .init(name: "DEBUG", syntax: "DEBUG subcommand ...", summary: "Internal debugging commands"),
        .init(name: "TIME", syntax: "TIME", summary: "Server time (seconds, microseconds)"),
        .init(name: "LASTSAVE", syntax: "LASTSAVE", summary: "UNIX time of last successful save"),
        .init(name: "SAVE", syntax: "SAVE", summary: "Synchronous save to disk"),
        .init(name: "BGSAVE", syntax: "BGSAVE [SCHEDULE]", summary: "Background save to disk"),
        .init(name: "BGREWRITEAOF", syntax: "BGREWRITEAOF", summary: "Background AOF rewrite"),
        .init(name: "SHUTDOWN", syntax: "SHUTDOWN [NOSAVE|SAVE] [NOW] [FORCE]", summary: "Stop the server"),
        .init(name: "REPLICAOF", syntax: "REPLICAOF host port | NO ONE", summary: "Set replication master"),
        .init(name: "SLAVEOF", syntax: "SLAVEOF host port | NO ONE", summary: "Deprecated alias of REPLICAOF"),
        .init(name: "FAILOVER", syntax: "FAILOVER [TO host port [FORCE]] [ABORT] [TIMEOUT ms]", summary: "Coordinated failover"),
        .init(name: "ROLE", syntax: "ROLE", summary: "Role in replication (master/replica/sentinel)"),
        .init(name: "WAIT", syntax: "WAIT numreplicas timeout", summary: "Wait for replica acks"),
        .init(name: "WAITAOF", syntax: "WAITAOF numlocal numreplicas timeout", summary: "Wait for AOF fsync"),
        .init(name: "LOLWUT", syntax: "LOLWUT [VERSION version]", summary: "Version-specific fun output"),
        .init(name: "MONITOR", syntax: "MONITOR", summary: "Stream every command the server processes"),

        // MARK: Generic keys
        .init(name: "DEL", syntax: "DEL key [key ...]", summary: "Delete keys"),
        .init(name: "UNLINK", syntax: "UNLINK key [key ...]", summary: "Delete keys asynchronously"),
        .init(name: "EXISTS", syntax: "EXISTS key [key ...]", summary: "Count how many keys exist"),
        .init(name: "TOUCH", syntax: "TOUCH key [key ...]", summary: "Update last-access without reading"),
        .init(name: "KEYS", syntax: "KEYS pattern", summary: "Find keys matching a pattern"),
        .init(name: "SCAN", syntax: "SCAN cursor [MATCH pat] [COUNT n] [TYPE t]", summary: "Incrementally iterate keys"),
        .init(name: "RANDOMKEY", syntax: "RANDOMKEY", summary: "Return a random key"),
        .init(name: "TYPE", syntax: "TYPE key", summary: "Type of the value at key"),
        .init(name: "OBJECT", syntax: "OBJECT ENCODING|FREQ|IDLETIME|REFCOUNT key", summary: "Inspect internal object"),
        .init(name: "TTL", syntax: "TTL key", summary: "Remaining TTL in seconds"),
        .init(name: "PTTL", syntax: "PTTL key", summary: "Remaining TTL in milliseconds"),
        .init(name: "EXPIRE", syntax: "EXPIRE key seconds [NX|XX|GT|LT]", summary: "Set a key's TTL in seconds"),
        .init(name: "PEXPIRE", syntax: "PEXPIRE key ms [NX|XX|GT|LT]", summary: "Set TTL in milliseconds"),
        .init(name: "EXPIREAT", syntax: "EXPIREAT key unix-seconds [NX|XX|GT|LT]", summary: "Expire at a UNIX time"),
        .init(name: "PEXPIREAT", syntax: "PEXPIREAT key unix-ms [NX|XX|GT|LT]", summary: "Expire at a UNIX time (ms)"),
        .init(name: "EXPIRETIME", syntax: "EXPIRETIME key", summary: "Absolute expiry (seconds)"),
        .init(name: "PEXPIRETIME", syntax: "PEXPIRETIME key", summary: "Absolute expiry (milliseconds)"),
        .init(name: "PERSIST", syntax: "PERSIST key", summary: "Remove a key's TTL"),
        .init(name: "RENAME", syntax: "RENAME key newkey", summary: "Rename a key"),
        .init(name: "RENAMENX", syntax: "RENAMENX key newkey", summary: "Rename only if new key absent"),
        .init(name: "COPY", syntax: "COPY src dst [DB n] [REPLACE]", summary: "Copy a key"),
        .init(name: "MOVE", syntax: "MOVE key db", summary: "Move a key to another DB"),
        .init(name: "DUMP", syntax: "DUMP key", summary: "Serialize a key"),
        .init(name: "RESTORE", syntax: "RESTORE key ttl serialized [REPLACE] [ABSTTL] ...", summary: "Restore a serialized key"),
        .init(name: "MIGRATE", syntax: "MIGRATE host port key|\"\" db timeout [COPY] [REPLACE] [KEYS ...]", summary: "Move a key to another instance"),
        .init(name: "SORT", syntax: "SORT key [BY pat] [LIMIT off n] [GET pat] [ASC|DESC] [ALPHA] [STORE dst]", summary: "Sort list/set/zset"),
        .init(name: "SORT_RO", syntax: "SORT_RO key [BY pat] [LIMIT off n] [GET pat] [ASC|DESC] [ALPHA]", summary: "Read-only SORT"),

        // MARK: Strings
        .init(name: "GET", syntax: "GET key", summary: "Get the value of a key"),
        .init(name: "SET", syntax: "SET key value [EX s|PX ms|EXAT|PXAT|KEEPTTL] [NX|XX] [GET]", summary: "Set the value of a key"),
        .init(name: "GETSET", syntax: "GETSET key value", summary: "Set and return old value"),
        .init(name: "GETDEL", syntax: "GETDEL key", summary: "Get and delete a key"),
        .init(name: "GETEX", syntax: "GETEX key [EX|PX|EXAT|PXAT|PERSIST]", summary: "Get and optionally set expiry"),
        .init(name: "SETEX", syntax: "SETEX key seconds value", summary: "Set with expiry (seconds)"),
        .init(name: "PSETEX", syntax: "PSETEX key ms value", summary: "Set with expiry (ms)"),
        .init(name: "SETNX", syntax: "SETNX key value", summary: "Set only if key does not exist"),
        .init(name: "APPEND", syntax: "APPEND key value", summary: "Append to a string"),
        .init(name: "STRLEN", syntax: "STRLEN key", summary: "Length of the string value"),
        .init(name: "GETRANGE", syntax: "GETRANGE key start end", summary: "Substring of the value"),
        .init(name: "SETRANGE", syntax: "SETRANGE key offset value", summary: "Overwrite part of the value"),
        .init(name: "SUBSTR", syntax: "SUBSTR key start end", summary: "Deprecated alias of GETRANGE"),
        .init(name: "INCR", syntax: "INCR key", summary: "Increment integer value by 1"),
        .init(name: "DECR", syntax: "DECR key", summary: "Decrement integer value by 1"),
        .init(name: "INCRBY", syntax: "INCRBY key increment", summary: "Increment by amount"),
        .init(name: "DECRBY", syntax: "DECRBY key decrement", summary: "Decrement by amount"),
        .init(name: "INCRBYFLOAT", syntax: "INCRBYFLOAT key increment", summary: "Increment by a float"),
        .init(name: "MGET", syntax: "MGET key [key ...]", summary: "Get multiple values"),
        .init(name: "MSET", syntax: "MSET key value [key value ...]", summary: "Set multiple values"),
        .init(name: "MSETNX", syntax: "MSETNX key value [key value ...]", summary: "Set multiple only if none exist"),
        .init(name: "LCS", syntax: "LCS key1 key2 [LEN] [IDX] [MINMATCHLEN n] [WITHMATCHLEN]", summary: "Longest common subsequence"),

        // MARK: Bitmaps
        .init(name: "SETBIT", syntax: "SETBIT key offset value", summary: "Set a bit"),
        .init(name: "GETBIT", syntax: "GETBIT key offset", summary: "Get a bit"),
        .init(name: "BITCOUNT", syntax: "BITCOUNT key [start end [BYTE|BIT]]", summary: "Count set bits"),
        .init(name: "BITPOS", syntax: "BITPOS key bit [start [end [BYTE|BIT]]]", summary: "Find first bit"),
        .init(name: "BITOP", syntax: "BITOP AND|OR|XOR|NOT dst key [key ...]", summary: "Bitwise operation"),
        .init(name: "BITFIELD", syntax: "BITFIELD key [GET|SET|INCRBY|OVERFLOW ...]", summary: "Arbitrary bitfield ops"),
        .init(name: "BITFIELD_RO", syntax: "BITFIELD_RO key GET type offset ...", summary: "Read-only BITFIELD"),

        // MARK: Hash
        .init(name: "HSET", syntax: "HSET key field value [field value ...]", summary: "Set hash fields"),
        .init(name: "HSETNX", syntax: "HSETNX key field value", summary: "Set field only if absent"),
        .init(name: "HGET", syntax: "HGET key field", summary: "Get a hash field"),
        .init(name: "HMGET", syntax: "HMGET key field [field ...]", summary: "Get multiple hash fields"),
        .init(name: "HMSET", syntax: "HMSET key field value [field value ...]", summary: "Deprecated alias of HSET"),
        .init(name: "HGETALL", syntax: "HGETALL key", summary: "Get all fields and values"),
        .init(name: "HDEL", syntax: "HDEL key field [field ...]", summary: "Delete hash fields"),
        .init(name: "HKEYS", syntax: "HKEYS key", summary: "All field names"),
        .init(name: "HVALS", syntax: "HVALS key", summary: "All values"),
        .init(name: "HLEN", syntax: "HLEN key", summary: "Number of fields"),
        .init(name: "HEXISTS", syntax: "HEXISTS key field", summary: "Whether a field exists"),
        .init(name: "HSTRLEN", syntax: "HSTRLEN key field", summary: "Length of a field's value"),
        .init(name: "HINCRBY", syntax: "HINCRBY key field increment", summary: "Increment a hash field"),
        .init(name: "HINCRBYFLOAT", syntax: "HINCRBYFLOAT key field increment", summary: "Increment field by a float"),
        .init(name: "HRANDFIELD", syntax: "HRANDFIELD key [count [WITHVALUES]]", summary: "Random field(s)"),
        .init(name: "HSCAN", syntax: "HSCAN key cursor [MATCH pat] [COUNT n] [NOVALUES]", summary: "Iterate hash fields"),

        // MARK: List
        .init(name: "LPUSH", syntax: "LPUSH key element [element ...]", summary: "Prepend to a list"),
        .init(name: "RPUSH", syntax: "RPUSH key element [element ...]", summary: "Append to a list"),
        .init(name: "LPUSHX", syntax: "LPUSHX key element [element ...]", summary: "Prepend only if list exists"),
        .init(name: "RPUSHX", syntax: "RPUSHX key element [element ...]", summary: "Append only if list exists"),
        .init(name: "LPOP", syntax: "LPOP key [count]", summary: "Pop from the head"),
        .init(name: "RPOP", syntax: "RPOP key [count]", summary: "Pop from the tail"),
        .init(name: "LMPOP", syntax: "LMPOP numkeys key [key ...] LEFT|RIGHT [COUNT n]", summary: "Pop from first non-empty list"),
        .init(name: "BLPOP", syntax: "BLPOP key [key ...] timeout", summary: "Blocking pop from head"),
        .init(name: "BRPOP", syntax: "BRPOP key [key ...] timeout", summary: "Blocking pop from tail"),
        .init(name: "BLMPOP", syntax: "BLMPOP timeout numkeys key [key ...] LEFT|RIGHT [COUNT n]", summary: "Blocking LMPOP"),
        .init(name: "LRANGE", syntax: "LRANGE key start stop", summary: "Range of list elements"),
        .init(name: "LLEN", syntax: "LLEN key", summary: "Length of the list"),
        .init(name: "LINDEX", syntax: "LINDEX key index", summary: "Element at index"),
        .init(name: "LSET", syntax: "LSET key index element", summary: "Set element at index"),
        .init(name: "LINSERT", syntax: "LINSERT key BEFORE|AFTER pivot element", summary: "Insert relative to a pivot"),
        .init(name: "LREM", syntax: "LREM key count element", summary: "Remove elements by value"),
        .init(name: "LTRIM", syntax: "LTRIM key start stop", summary: "Trim to a range"),
        .init(name: "LPOS", syntax: "LPOS key element [RANK r] [COUNT n] [MAXLEN m]", summary: "Index of matching element(s)"),
        .init(name: "LMOVE", syntax: "LMOVE src dst LEFT|RIGHT LEFT|RIGHT", summary: "Move element between lists"),
        .init(name: "BLMOVE", syntax: "BLMOVE src dst LEFT|RIGHT LEFT|RIGHT timeout", summary: "Blocking LMOVE"),
        .init(name: "RPOPLPUSH", syntax: "RPOPLPUSH src dst", summary: "Pop tail, push head (deprecated)"),
        .init(name: "BRPOPLPUSH", syntax: "BRPOPLPUSH src dst timeout", summary: "Blocking RPOPLPUSH (deprecated)"),

        // MARK: Set
        .init(name: "SADD", syntax: "SADD key member [member ...]", summary: "Add set members"),
        .init(name: "SREM", syntax: "SREM key member [member ...]", summary: "Remove set members"),
        .init(name: "SMEMBERS", syntax: "SMEMBERS key", summary: "All set members"),
        .init(name: "SCARD", syntax: "SCARD key", summary: "Set cardinality"),
        .init(name: "SISMEMBER", syntax: "SISMEMBER key member", summary: "Whether member is in set"),
        .init(name: "SMISMEMBER", syntax: "SMISMEMBER key member [member ...]", summary: "Membership of multiple members"),
        .init(name: "SPOP", syntax: "SPOP key [count]", summary: "Remove and return random members"),
        .init(name: "SRANDMEMBER", syntax: "SRANDMEMBER key [count]", summary: "Random members (no removal)"),
        .init(name: "SMOVE", syntax: "SMOVE src dst member", summary: "Move a member between sets"),
        .init(name: "SINTER", syntax: "SINTER key [key ...]", summary: "Intersect sets"),
        .init(name: "SINTERCARD", syntax: "SINTERCARD numkeys key [key ...] [LIMIT n]", summary: "Cardinality of intersection"),
        .init(name: "SINTERSTORE", syntax: "SINTERSTORE dst key [key ...]", summary: "Store intersection"),
        .init(name: "SUNION", syntax: "SUNION key [key ...]", summary: "Union of sets"),
        .init(name: "SUNIONSTORE", syntax: "SUNIONSTORE dst key [key ...]", summary: "Store union"),
        .init(name: "SDIFF", syntax: "SDIFF key [key ...]", summary: "Difference of sets"),
        .init(name: "SDIFFSTORE", syntax: "SDIFFSTORE dst key [key ...]", summary: "Store difference"),
        .init(name: "SSCAN", syntax: "SSCAN key cursor [MATCH pat] [COUNT n]", summary: "Iterate set members"),

        // MARK: Sorted set
        .init(name: "ZADD", syntax: "ZADD key [NX|XX] [GT|LT] [CH] [INCR] score member ...", summary: "Add to sorted set"),
        .init(name: "ZREM", syntax: "ZREM key member [member ...]", summary: "Remove members"),
        .init(name: "ZSCORE", syntax: "ZSCORE key member", summary: "Score of a member"),
        .init(name: "ZMSCORE", syntax: "ZMSCORE key member [member ...]", summary: "Scores of multiple members"),
        .init(name: "ZCARD", syntax: "ZCARD key", summary: "Sorted-set cardinality"),
        .init(name: "ZCOUNT", syntax: "ZCOUNT key min max", summary: "Count members in score range"),
        .init(name: "ZLEXCOUNT", syntax: "ZLEXCOUNT key min max", summary: "Count members in lex range"),
        .init(name: "ZINCRBY", syntax: "ZINCRBY key increment member", summary: "Increment a member's score"),
        .init(name: "ZRANK", syntax: "ZRANK key member [WITHSCORE]", summary: "Rank (low to high)"),
        .init(name: "ZREVRANK", syntax: "ZREVRANK key member [WITHSCORE]", summary: "Rank (high to low)"),
        .init(name: "ZRANGE", syntax: "ZRANGE key start stop [BYSCORE|BYLEX] [REV] [LIMIT o n] [WITHSCORES]", summary: "Range query"),
        .init(name: "ZREVRANGE", syntax: "ZREVRANGE key start stop [WITHSCORES]", summary: "Range by index, reversed"),
        .init(name: "ZRANGEBYSCORE", syntax: "ZRANGEBYSCORE key min max [WITHSCORES] [LIMIT o n]", summary: "Range by score"),
        .init(name: "ZREVRANGEBYSCORE", syntax: "ZREVRANGEBYSCORE key max min [WITHSCORES] [LIMIT o n]", summary: "Range by score, reversed"),
        .init(name: "ZRANGEBYLEX", syntax: "ZRANGEBYLEX key min max [LIMIT o n]", summary: "Range by lexicographic order"),
        .init(name: "ZREVRANGEBYLEX", syntax: "ZREVRANGEBYLEX key max min [LIMIT o n]", summary: "Range by lex, reversed"),
        .init(name: "ZRANGESTORE", syntax: "ZRANGESTORE dst src min max [BYSCORE|BYLEX] [REV] [LIMIT o n]", summary: "Store a range query"),
        .init(name: "ZPOPMIN", syntax: "ZPOPMIN key [count]", summary: "Pop lowest-scoring members"),
        .init(name: "ZPOPMAX", syntax: "ZPOPMAX key [count]", summary: "Pop highest-scoring members"),
        .init(name: "BZPOPMIN", syntax: "BZPOPMIN key [key ...] timeout", summary: "Blocking ZPOPMIN"),
        .init(name: "BZPOPMAX", syntax: "BZPOPMAX key [key ...] timeout", summary: "Blocking ZPOPMAX"),
        .init(name: "ZMPOP", syntax: "ZMPOP numkeys key [key ...] MIN|MAX [COUNT n]", summary: "Pop from first non-empty zset"),
        .init(name: "BZMPOP", syntax: "BZMPOP timeout numkeys key [key ...] MIN|MAX [COUNT n]", summary: "Blocking ZMPOP"),
        .init(name: "ZRANDMEMBER", syntax: "ZRANDMEMBER key [count [WITHSCORES]]", summary: "Random member(s)"),
        .init(name: "ZREMRANGEBYRANK", syntax: "ZREMRANGEBYRANK key start stop", summary: "Remove by rank range"),
        .init(name: "ZREMRANGEBYSCORE", syntax: "ZREMRANGEBYSCORE key min max", summary: "Remove by score range"),
        .init(name: "ZREMRANGEBYLEX", syntax: "ZREMRANGEBYLEX key min max", summary: "Remove by lex range"),
        .init(name: "ZDIFF", syntax: "ZDIFF numkeys key [key ...] [WITHSCORES]", summary: "Difference of zsets"),
        .init(name: "ZDIFFSTORE", syntax: "ZDIFFSTORE dst numkeys key [key ...]", summary: "Store zset difference"),
        .init(name: "ZINTER", syntax: "ZINTER numkeys key [key ...] [WEIGHTS ...] [AGGREGATE ...] [WITHSCORES]", summary: "Intersect zsets"),
        .init(name: "ZINTERCARD", syntax: "ZINTERCARD numkeys key [key ...] [LIMIT n]", summary: "Cardinality of zset intersection"),
        .init(name: "ZINTERSTORE", syntax: "ZINTERSTORE dst numkeys key [key ...] [WEIGHTS ...] [AGGREGATE ...]", summary: "Store zset intersection"),
        .init(name: "ZUNION", syntax: "ZUNION numkeys key [key ...] [WEIGHTS ...] [AGGREGATE ...] [WITHSCORES]", summary: "Union of zsets"),
        .init(name: "ZUNIONSTORE", syntax: "ZUNIONSTORE dst numkeys key [key ...] [WEIGHTS ...] [AGGREGATE ...]", summary: "Store zset union"),
        .init(name: "ZSCAN", syntax: "ZSCAN key cursor [MATCH pat] [COUNT n]", summary: "Iterate sorted-set members"),

        // MARK: Streams
        .init(name: "XADD", syntax: "XADD key [NOMKSTREAM] [MAXLEN|MINID ...] *|id field value ...", summary: "Append an entry"),
        .init(name: "XREAD", syntax: "XREAD [COUNT n] [BLOCK ms] STREAMS key [key ...] id [id ...]", summary: "Read entries"),
        .init(name: "XRANGE", syntax: "XRANGE key start end [COUNT n]", summary: "Range of entries"),
        .init(name: "XREVRANGE", syntax: "XREVRANGE key end start [COUNT n]", summary: "Range of entries, reversed"),
        .init(name: "XLEN", syntax: "XLEN key", summary: "Number of entries"),
        .init(name: "XDEL", syntax: "XDEL key id [id ...]", summary: "Delete entries"),
        .init(name: "XTRIM", syntax: "XTRIM key MAXLEN|MINID [=|~] threshold [LIMIT n]", summary: "Trim the stream"),
        .init(name: "XINFO", syntax: "XINFO STREAM|GROUPS|CONSUMERS key ...", summary: "Stream introspection"),
        .init(name: "XGROUP", syntax: "XGROUP CREATE|SETID|DESTROY|CREATECONSUMER|DELCONSUMER ...", summary: "Consumer-group management"),
        .init(name: "XREADGROUP", syntax: "XREADGROUP GROUP g c [COUNT n] [BLOCK ms] [NOACK] STREAMS key ... id ...", summary: "Read as a consumer group"),
        .init(name: "XACK", syntax: "XACK key group id [id ...]", summary: "Acknowledge processed entries"),
        .init(name: "XCLAIM", syntax: "XCLAIM key group consumer min-idle id [id ...] [options]", summary: "Claim pending entries"),
        .init(name: "XAUTOCLAIM", syntax: "XAUTOCLAIM key group consumer min-idle start [COUNT n] [JUSTID]", summary: "Auto-claim pending entries"),
        .init(name: "XPENDING", syntax: "XPENDING key group [[IDLE ms] start end count [consumer]]", summary: "Inspect pending entries"),
        .init(name: "XSETID", syntax: "XSETID key id [ENTRIESADDED n] [MAXDELETEDID id]", summary: "Set the last stream ID"),

        // MARK: HyperLogLog
        .init(name: "PFADD", syntax: "PFADD key [element ...]", summary: "Add elements to a HyperLogLog"),
        .init(name: "PFCOUNT", syntax: "PFCOUNT key [key ...]", summary: "Approximate cardinality"),
        .init(name: "PFMERGE", syntax: "PFMERGE dst src [src ...]", summary: "Merge HyperLogLogs"),

        // MARK: Geo
        .init(name: "GEOADD", syntax: "GEOADD key [NX|XX] [CH] lon lat member ...", summary: "Add geospatial items"),
        .init(name: "GEOPOS", syntax: "GEOPOS key member [member ...]", summary: "Positions of members"),
        .init(name: "GEODIST", syntax: "GEODIST key m1 m2 [m|km|mi|ft]", summary: "Distance between members"),
        .init(name: "GEOHASH", syntax: "GEOHASH key member [member ...]", summary: "Geohash strings"),
        .init(name: "GEOSEARCH", syntax: "GEOSEARCH key FROMMEMBER|FROMLONLAT BYRADIUS|BYBOX ... [ASC|DESC] [COUNT n]", summary: "Search within an area"),
        .init(name: "GEOSEARCHSTORE", syntax: "GEOSEARCHSTORE dst src ...", summary: "Store a geo search"),

        // MARK: Pub/Sub
        .init(name: "SUBSCRIBE", syntax: "SUBSCRIBE channel [channel ...]", summary: "Subscribe to channels"),
        .init(name: "UNSUBSCRIBE", syntax: "UNSUBSCRIBE [channel ...]", summary: "Unsubscribe from channels"),
        .init(name: "PSUBSCRIBE", syntax: "PSUBSCRIBE pattern [pattern ...]", summary: "Subscribe by pattern"),
        .init(name: "PUNSUBSCRIBE", syntax: "PUNSUBSCRIBE [pattern ...]", summary: "Unsubscribe by pattern"),
        .init(name: "SSUBSCRIBE", syntax: "SSUBSCRIBE shardchannel [shardchannel ...]", summary: "Subscribe to shard channels"),
        .init(name: "SUNSUBSCRIBE", syntax: "SUNSUBSCRIBE [shardchannel ...]", summary: "Unsubscribe from shard channels"),
        .init(name: "PUBLISH", syntax: "PUBLISH channel message", summary: "Publish a message"),
        .init(name: "SPUBLISH", syntax: "SPUBLISH shardchannel message", summary: "Publish to a shard channel"),
        .init(name: "PUBSUB", syntax: "PUBSUB CHANNELS|NUMSUB|NUMPAT|SHARDCHANNELS|SHARDNUMSUB ...", summary: "Introspect pub/sub state"),

        // MARK: Transactions
        .init(name: "MULTI", syntax: "MULTI", summary: "Start a transaction"),
        .init(name: "EXEC", syntax: "EXEC", summary: "Execute a transaction"),
        .init(name: "DISCARD", syntax: "DISCARD", summary: "Discard a transaction"),
        .init(name: "WATCH", syntax: "WATCH key [key ...]", summary: "Watch keys for CAS"),
        .init(name: "UNWATCH", syntax: "UNWATCH", summary: "Forget watched keys"),

        // MARK: Scripting & Functions
        .init(name: "EVAL", syntax: "EVAL script numkeys [key ...] [arg ...]", summary: "Run a Lua script"),
        .init(name: "EVAL_RO", syntax: "EVAL_RO script numkeys [key ...] [arg ...]", summary: "Read-only EVAL"),
        .init(name: "EVALSHA", syntax: "EVALSHA sha1 numkeys [key ...] [arg ...]", summary: "Run a cached Lua script"),
        .init(name: "EVALSHA_RO", syntax: "EVALSHA_RO sha1 numkeys [key ...] [arg ...]", summary: "Read-only EVALSHA"),
        .init(name: "SCRIPT", syntax: "SCRIPT LOAD|EXISTS|FLUSH|KILL ...", summary: "Manage the script cache"),
        .init(name: "FUNCTION", syntax: "FUNCTION LOAD|DELETE|FLUSH|LIST|DUMP|RESTORE|STATS|KILL ...", summary: "Manage server-side functions"),
        .init(name: "FCALL", syntax: "FCALL function numkeys [key ...] [arg ...]", summary: "Call a function"),
        .init(name: "FCALL_RO", syntax: "FCALL_RO function numkeys [key ...] [arg ...]", summary: "Call a read-only function"),

        // MARK: RedisJSON module
        .init(name: "JSON.GET", syntax: "JSON.GET key [path ...]", summary: "Get JSON value at path(s)"),
        .init(name: "JSON.SET", syntax: "JSON.SET key path value [NX|XX]", summary: "Set JSON value at path"),
        .init(name: "JSON.DEL", syntax: "JSON.DEL key [path]", summary: "Delete JSON value at path"),
        .init(name: "JSON.FORGET", syntax: "JSON.FORGET key [path]", summary: "Alias of JSON.DEL"),
        .init(name: "JSON.TYPE", syntax: "JSON.TYPE key [path]", summary: "Type of JSON value at path"),
        .init(name: "JSON.MGET", syntax: "JSON.MGET key [key ...] path", summary: "Get a path from multiple keys"),
        .init(name: "JSON.MSET", syntax: "JSON.MSET key path value [key path value ...]", summary: "Set multiple JSON values"),
        .init(name: "JSON.MERGE", syntax: "JSON.MERGE key path value", summary: "Merge JSON value at path"),
        .init(name: "JSON.CLEAR", syntax: "JSON.CLEAR key [path]", summary: "Clear container / zero number"),
        .init(name: "JSON.NUMINCRBY", syntax: "JSON.NUMINCRBY key path number", summary: "Increment a JSON number"),
        .init(name: "JSON.NUMMULTBY", syntax: "JSON.NUMMULTBY key path number", summary: "Multiply a JSON number"),
        .init(name: "JSON.STRAPPEND", syntax: "JSON.STRAPPEND key [path] value", summary: "Append to a JSON string"),
        .init(name: "JSON.STRLEN", syntax: "JSON.STRLEN key [path]", summary: "Length of a JSON string"),
        .init(name: "JSON.TOGGLE", syntax: "JSON.TOGGLE key path", summary: "Toggle a JSON boolean"),
        .init(name: "JSON.ARRAPPEND", syntax: "JSON.ARRAPPEND key path value [value ...]", summary: "Append to a JSON array"),
        .init(name: "JSON.ARRINSERT", syntax: "JSON.ARRINSERT key path index value [value ...]", summary: "Insert into a JSON array"),
        .init(name: "JSON.ARRINDEX", syntax: "JSON.ARRINDEX key path value [start [stop]]", summary: "Find value in a JSON array"),
        .init(name: "JSON.ARRLEN", syntax: "JSON.ARRLEN key [path]", summary: "Length of a JSON array"),
        .init(name: "JSON.ARRPOP", syntax: "JSON.ARRPOP key [path [index]]", summary: "Pop from a JSON array"),
        .init(name: "JSON.ARRTRIM", syntax: "JSON.ARRTRIM key path start stop", summary: "Trim a JSON array"),
        .init(name: "JSON.OBJKEYS", syntax: "JSON.OBJKEYS key [path]", summary: "Keys of a JSON object"),
        .init(name: "JSON.OBJLEN", syntax: "JSON.OBJLEN key [path]", summary: "Number of keys in a JSON object"),
        .init(name: "JSON.RESP", syntax: "JSON.RESP key [path]", summary: "JSON value in RESP form"),
    ]

    /// Subcommands for container commands, so the Console can suggest the second
    /// token (e.g. after "CONFIG "). Keyed by the uppercased container name; each
    /// entry's `name` is the full "CONTAINER SUB" string.
    static let subcommands: [String: [RedisCommandInfo]] = [
        "CONFIG": [
            .init(name: "CONFIG GET", syntax: "CONFIG GET parameter [parameter ...]", summary: "Read config parameters"),
            .init(name: "CONFIG SET", syntax: "CONFIG SET parameter value [parameter value ...]", summary: "Set config parameters"),
            .init(name: "CONFIG RESETSTAT", syntax: "CONFIG RESETSTAT", summary: "Reset INFO statistics"),
            .init(name: "CONFIG REWRITE", syntax: "CONFIG REWRITE", summary: "Rewrite the config file"),
        ],
        "CLIENT": [
            .init(name: "CLIENT ID", syntax: "CLIENT ID", summary: "Current connection ID"),
            .init(name: "CLIENT GETNAME", syntax: "CLIENT GETNAME", summary: "Connection name"),
            .init(name: "CLIENT SETNAME", syntax: "CLIENT SETNAME name", summary: "Set connection name"),
            .init(name: "CLIENT SETINFO", syntax: "CLIENT SETINFO lib-name|lib-ver value", summary: "Set client library info"),
            .init(name: "CLIENT LIST", syntax: "CLIENT LIST [TYPE t] [ID id ...]", summary: "List client connections"),
            .init(name: "CLIENT INFO", syntax: "CLIENT INFO", summary: "Info about the current connection"),
            .init(name: "CLIENT KILL", syntax: "CLIENT KILL ...", summary: "Close client connections"),
            .init(name: "CLIENT NO-EVICT", syntax: "CLIENT NO-EVICT ON|OFF", summary: "Protect from eviction"),
            .init(name: "CLIENT NO-TOUCH", syntax: "CLIENT NO-TOUCH ON|OFF", summary: "Don't update LRU/LFU"),
            .init(name: "CLIENT PAUSE", syntax: "CLIENT PAUSE timeout [WRITE|ALL]", summary: "Pause processing"),
            .init(name: "CLIENT UNPAUSE", syntax: "CLIENT UNPAUSE", summary: "Resume processing"),
            .init(name: "CLIENT REPLY", syntax: "CLIENT REPLY ON|OFF|SKIP", summary: "Control server replies"),
        ],
        "CLUSTER": [
            .init(name: "CLUSTER INFO", syntax: "CLUSTER INFO", summary: "Cluster state"),
            .init(name: "CLUSTER NODES", syntax: "CLUSTER NODES", summary: "Cluster nodes config"),
            .init(name: "CLUSTER SLOTS", syntax: "CLUSTER SLOTS", summary: "Slot-to-node mapping"),
            .init(name: "CLUSTER SHARDS", syntax: "CLUSTER SHARDS", summary: "Shard topology"),
            .init(name: "CLUSTER MYID", syntax: "CLUSTER MYID", summary: "This node's ID"),
            .init(name: "CLUSTER KEYSLOT", syntax: "CLUSTER KEYSLOT key", summary: "Slot for a key"),
            .init(name: "CLUSTER COUNTKEYSINSLOT", syntax: "CLUSTER COUNTKEYSINSLOT slot", summary: "Keys in a slot"),
            .init(name: "CLUSTER GETKEYSINSLOT", syntax: "CLUSTER GETKEYSINSLOT slot count", summary: "Keys in a slot"),
            .init(name: "CLUSTER RESET", syntax: "CLUSTER RESET [HARD|SOFT]", summary: "Reset the node"),
        ],
        "COMMAND": [
            .init(name: "COMMAND COUNT", syntax: "COMMAND COUNT", summary: "Number of commands"),
            .init(name: "COMMAND DOCS", syntax: "COMMAND DOCS [command ...]", summary: "Command documentation"),
            .init(name: "COMMAND INFO", syntax: "COMMAND INFO [command ...]", summary: "Command details"),
            .init(name: "COMMAND LIST", syntax: "COMMAND LIST [FILTERBY ...]", summary: "List command names"),
            .init(name: "COMMAND GETKEYS", syntax: "COMMAND GETKEYS command [arg ...]", summary: "Keys a command touches"),
        ],
        "MEMORY": [
            .init(name: "MEMORY USAGE", syntax: "MEMORY USAGE key [SAMPLES n]", summary: "Memory used by a key"),
            .init(name: "MEMORY DOCTOR", syntax: "MEMORY DOCTOR", summary: "Memory health report"),
            .init(name: "MEMORY STATS", syntax: "MEMORY STATS", summary: "Detailed memory stats"),
            .init(name: "MEMORY PURGE", syntax: "MEMORY PURGE", summary: "Ask allocator to release memory"),
        ],
        "OBJECT": [
            .init(name: "OBJECT ENCODING", syntax: "OBJECT ENCODING key", summary: "Internal encoding"),
            .init(name: "OBJECT FREQ", syntax: "OBJECT FREQ key", summary: "Access frequency (LFU)"),
            .init(name: "OBJECT IDLETIME", syntax: "OBJECT IDLETIME key", summary: "Idle time (LRU)"),
            .init(name: "OBJECT REFCOUNT", syntax: "OBJECT REFCOUNT key", summary: "Reference count"),
        ],
        "ACL": [
            .init(name: "ACL WHOAMI", syntax: "ACL WHOAMI", summary: "Current username"),
            .init(name: "ACL LIST", syntax: "ACL LIST", summary: "List ACL rules"),
            .init(name: "ACL CAT", syntax: "ACL CAT [category]", summary: "Command categories"),
            .init(name: "ACL GETUSER", syntax: "ACL GETUSER username", summary: "Rules for a user"),
            .init(name: "ACL SETUSER", syntax: "ACL SETUSER username [rule ...]", summary: "Create/modify a user"),
            .init(name: "ACL DELUSER", syntax: "ACL DELUSER username [username ...]", summary: "Delete users"),
            .init(name: "ACL USERS", syntax: "ACL USERS", summary: "List usernames"),
            .init(name: "ACL GENPASS", syntax: "ACL GENPASS [bits]", summary: "Generate a password"),
        ],
        "FUNCTION": [
            .init(name: "FUNCTION LOAD", syntax: "FUNCTION LOAD [REPLACE] code", summary: "Load a function library"),
            .init(name: "FUNCTION DELETE", syntax: "FUNCTION DELETE library", summary: "Delete a library"),
            .init(name: "FUNCTION FLUSH", syntax: "FUNCTION FLUSH [ASYNC|SYNC]", summary: "Delete all libraries"),
            .init(name: "FUNCTION LIST", syntax: "FUNCTION LIST [LIBRARYNAME name] [WITHCODE]", summary: "List libraries"),
            .init(name: "FUNCTION DUMP", syntax: "FUNCTION DUMP", summary: "Serialize all libraries"),
            .init(name: "FUNCTION RESTORE", syntax: "FUNCTION RESTORE payload [FLUSH|APPEND|REPLACE]", summary: "Restore libraries"),
            .init(name: "FUNCTION STATS", syntax: "FUNCTION STATS", summary: "Running function stats"),
            .init(name: "FUNCTION KILL", syntax: "FUNCTION KILL", summary: "Kill the running function"),
        ],
        "SCRIPT": [
            .init(name: "SCRIPT LOAD", syntax: "SCRIPT LOAD script", summary: "Cache a Lua script"),
            .init(name: "SCRIPT EXISTS", syntax: "SCRIPT EXISTS sha1 [sha1 ...]", summary: "Check cached scripts"),
            .init(name: "SCRIPT FLUSH", syntax: "SCRIPT FLUSH [ASYNC|SYNC]", summary: "Flush the script cache"),
            .init(name: "SCRIPT KILL", syntax: "SCRIPT KILL", summary: "Kill the running script"),
        ],
        "XINFO": [
            .init(name: "XINFO STREAM", syntax: "XINFO STREAM key [FULL [COUNT n]]", summary: "Stream details"),
            .init(name: "XINFO GROUPS", syntax: "XINFO GROUPS key", summary: "Consumer groups"),
            .init(name: "XINFO CONSUMERS", syntax: "XINFO CONSUMERS key group", summary: "Consumers in a group"),
        ],
        "XGROUP": [
            .init(name: "XGROUP CREATE", syntax: "XGROUP CREATE key group id|$ [MKSTREAM]", summary: "Create a consumer group"),
            .init(name: "XGROUP SETID", syntax: "XGROUP SETID key group id|$", summary: "Set group's last-delivered ID"),
            .init(name: "XGROUP DESTROY", syntax: "XGROUP DESTROY key group", summary: "Destroy a consumer group"),
            .init(name: "XGROUP CREATECONSUMER", syntax: "XGROUP CREATECONSUMER key group consumer", summary: "Create a consumer"),
            .init(name: "XGROUP DELCONSUMER", syntax: "XGROUP DELCONSUMER key group consumer", summary: "Delete a consumer"),
        ],
        "PUBSUB": [
            .init(name: "PUBSUB CHANNELS", syntax: "PUBSUB CHANNELS [pattern]", summary: "Active channels"),
            .init(name: "PUBSUB NUMSUB", syntax: "PUBSUB NUMSUB [channel ...]", summary: "Subscribers per channel"),
            .init(name: "PUBSUB NUMPAT", syntax: "PUBSUB NUMPAT", summary: "Number of pattern subscriptions"),
            .init(name: "PUBSUB SHARDCHANNELS", syntax: "PUBSUB SHARDCHANNELS [pattern]", summary: "Active shard channels"),
            .init(name: "PUBSUB SHARDNUMSUB", syntax: "PUBSUB SHARDNUMSUB [channel ...]", summary: "Subscribers per shard channel"),
        ],
        "SLOWLOG": [
            .init(name: "SLOWLOG GET", syntax: "SLOWLOG GET [count]", summary: "Read the slow log"),
            .init(name: "SLOWLOG LEN", syntax: "SLOWLOG LEN", summary: "Slow log length"),
            .init(name: "SLOWLOG RESET", syntax: "SLOWLOG RESET", summary: "Clear the slow log"),
        ],
        "LATENCY": [
            .init(name: "LATENCY HISTORY", syntax: "LATENCY HISTORY event", summary: "Latency samples for an event"),
            .init(name: "LATENCY LATEST", syntax: "LATENCY LATEST", summary: "Latest latency spikes"),
            .init(name: "LATENCY RESET", syntax: "LATENCY RESET [event ...]", summary: "Reset latency data"),
            .init(name: "LATENCY DOCTOR", syntax: "LATENCY DOCTOR", summary: "Latency analysis report"),
            .init(name: "LATENCY GRAPH", syntax: "LATENCY GRAPH event", summary: "ASCII latency graph"),
        ],
    ]

    private static let byName: [String: RedisCommandInfo] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })

    /// Commands whose name starts with `prefix` (case-insensitive), name-sorted.
    static func matching(prefix: String) -> [RedisCommandInfo] {
        let p = prefix.uppercased()
        guard !p.isEmpty else { return [] }
        return all.filter { $0.name.hasPrefix(p) }.sorted { $0.name < $1.name }
    }

    static func info(for name: String) -> RedisCommandInfo? {
        byName[name.uppercased()]
    }

    /// Whether a command has documented subcommands (a container command).
    static func hasSubcommands(_ command: String) -> Bool {
        subcommands[command.uppercased()] != nil
    }

    /// Subcommands of `container` whose subcommand token starts with `prefix`.
    static func subcommandsMatching(container: String, prefix: String) -> [RedisCommandInfo] {
        guard let subs = subcommands[container.uppercased()] else { return [] }
        let full = (container.uppercased() + " " + prefix.uppercased())
        return subs.filter { $0.name.hasPrefix(full) }.sorted { $0.name < $1.name }
    }
}
