%%% A collection of record structures used throughout the Arweave server.

%% @doc How nodes identify they are on the same network.
-define(NETWORK_NAME, "arweave.N.1").

%% @doc Current release number of the arweave client software.
-define(CLIENT_VERSION, 3).

%% @doc The current build number -- incremented for every release.
-define(RELEASE_NUMBER, 9).

-define(DEFAULT_REQUEST_HEADERS,
	[
		{<<"X-Version">>, list_to_binary(integer_to_list(?RELEASE_NUMBER))}
	]).

-define(DEFAULT_RESPONSE_HEADERS,
	[
		{<<"Access-Control-Allow-Origin">>, <<"*">>}
	]).

%% @doc Specifies whether the software should be run in debug mode
%% (excuting ifdef code blocks).
%% WARNING: Only define debug during testing.
%-define(DEBUG, debug).

%% @doc Default auto-update watch address.
-define(DEFAULT_UPDATE_ADDR, "8L1NmHR2qY9wH-AqgsOmdw98FMwrdIzTS5-bJi9YDZ4").

%% @doc Should ar:report_console/1 /actually/ report to the console?
-define(SILENT, true).

%% @doc The hashing algorithm used to calculate wallet addresses
-define(HASH_ALG, sha256).

%% @doc The hashing algorithm used to verify that the weave has not been
%% tampered with.
-define(MINING_HASH_ALG, sha384).
-define(HASH_SZ, 256).
-define(SIGN_ALG, rsa).
-define(PRIV_KEY_SZ, 4096).

%% @doc NB: Setting the default difficulty high will cause TNT to fail.
-define(DEFAULT_DIFF, 8).

-ifdef(DEBUG).
-define(MIN_DIFF, ?DEFAULT_DIFF).
-endif.

-ifndef(MIN_DIFF).
-define(MIN_DIFF, 31).
-endif.

-ifndef(TARGET_TIME).
-define(TARGET_TIME, 120).
-endif.

-ifndef(RETARGET_BLOCKS).
-define(RETARGET_BLOCKS, 10).
-endif.

-define(RETARGET_TOLERANCE, 0.1).
-define(BLOCK_PAD_SIZE, (1024*1024*1)).

%% @doc The total supply of tokens in the Genesis block,
-define(GENESIS_TOKENS, 55000000).

%% @doc Winstons per AR.
-define(WINSTON_PER_AR, 1000000000000).

%% The base cost of a byte in AR
-define(BASE_BYTES_PER_AR, 10000000).

%% Base wallet generation fee
-define(WALLET_GEN_FEE, 250000000000).

%% @doc The minimum cost per byte for a single TX.
-define(COST_PER_BYTE, (?WINSTON_PER_AR div ?BASE_BYTES_PER_AR)).

%% The difficulty "center" at which 1 byte costs ?BASE_BYTES_PER_AR
-define(DIFF_CENTER, 40).

%% @doc The amount of the weave to store. 1.0 = 100%; 0.5 = 50% etc.
-define(WEAVE_STORE_AMT, 1.0).

%% @doc The number of blocks behind the most recent block to store.
-define(STORE_BLOCKS_BEHIND_CURRENT, 50).

%% Speed to run the network at when simulating.
-define(DEBUG_TIME_SCALAR, 1.0).

%% @doc Length of time to wait before giving up on test(s).
-define(TEST_TIMEOUT, 5 * 60).

%% @doc Calculate MS to wait in order to hit target block time.
-define(DEFAULT_MINING_DELAY,
    ((?TARGET_TIME * 1000) div erlang:trunc(math:pow(2, ?DEFAULT_DIFF - 1)))).

%% @doc The maximum size of a single POST body.
-define(MAX_BODY_SIZE, 3 * 1024 * 1024).

%% @doc Default timeout value for network requests.
-define(NET_TIMEOUT, 300 * 1000).

%% @doc Default timeout value for local requests
-define(LOCAL_NET_TIMEOUT, 30000).

%% @doc Default timeout for initial request
-define(CONNECT_TIMEOUT, 25 * 1000).

%% @doc Default time to wait after a failed join to retry
-define(REJOIN_TIMEOUT, 3000).

%% @doc The amount of time to wait before refreshing miner data in case of a
%% difficulty change.
-define(REFRESH_MINE_DATA_TIMER, 60000).

%% @doc Time between attempts to find optimise peers.
-define(GET_MORE_PEERS_TIME,  240 * 1000).

%% @doc Time to wait before not ignoring bad peers.
-define(IGNORE_PEERS_TIME, 5 * 60 * 1000).

%% @doc Number of transfers for which not to score (and potentially drop)
%% new peers.
-define(PEER_GRACE_PERIOD, 100).

%% @doc Never drop to lower than this number of peers.
-define(MINIMUM_PEERS, 4).

%% @doc Never have more than this number of peers (new peers excluded).
-define(MAXIMUM_PEERS, 20).

%% @doc Amount of peers without a given transaction to send a new transaction to.
-define(NUM_REGOSSIP_TX, 20).

%% Maximum nunber of requests allowed by an IP in any 30 second period.
-define(MAX_REQUESTS, 450).

%% @doc Delay before mining rewards manifest.
-define(REWARD_DELAY, ?BLOCK_PER_YEAR/4).

%% @doc List of default peers to connect
-define(DEFAULT_PEER_LIST, []).

%% @doc Peers to never add to peer list
-define(PEER_PERMANENT_BLACKLIST,[]).

%% @doc Length of time to wait (seconds) before dropping after last activity
-define(PEER_TIMEOUT, 480).

%% @doc Log output directory
-define(LOG_DIR, "logs").
-define(BLOCK_DIR, "blocks").
-define(BLOCK_ENC_DIR, "blocks/enc").
-define(TX_DIR, "txs").

%% @doc Backup block hash list storage directory.
-define(HASH_LIST_DIR, "hash_lists").
%% @doc Directory for storing unique wallet lists.
-define(WALLET_LIST_DIR, "wallet_lists").

%% @doc Port to use for cross-machine message transfer.
-define(DEFAULT_HTTP_IFACE_PORT, 1984).

%% @doc Number of mining processes to spawn
%% For best mining, this is set to the number of available processers minus 1.
%% More mining can be performed with every core utilised, but at significant
%% cost to node performance.
-define(NUM_MINING_PROCESSES, max(1, (erlang:system_info(schedulers_online) - 1))).

%% @doc Target number of blocks per year.
-define(BLOCK_PER_YEAR, 525600/(?TARGET_TIME/60) ).

%% @doc A block on the weave.
-record(block, {
	nonce = <<>>, % The nonce used to satisfy the mining problem when mined
	previous_block = <<>>, % indep_hash of the previous block in the weave
	timestamp = ar:timestamp(), % Unix time of block discovery
	last_retarget = -1, % Unix timestamp of the last difficulty retarget
	diff = ?DEFAULT_DIFF, % Puzzle difficulty, number of preceeding zeroes.
	height = -1, % How many blocks have passed since the Genesis block?
	hash = <<>>, % A hash of this block, the previous block and the recall block.
	indep_hash = [], % A hash of this block JSON encoded. (TODO: Shouldn't it be a binary as it is a hash?)
	txs = [], % A list of transaction records associated with this block.
	hash_list = unset, % A list of all previous indep hashes.
	wallet_list = [], % A map of wallet balances, or undefined.
    reward_addr = unclaimed, % Address to credit mining reward or unclaimed.
    tags = [], % Miner specified tags to store with the block.
	reward_pool = 0, % Current pool of mining reward.
	weave_size = 0, % Current size of the weave in bytes (counts tx data fields).
	block_size = 0 % The size of the transactions inside this block.
}).

%% @doc A transaction, as stored in a block.
-record(tx, {
	id = <<>>, % TX UID (Signature hash).
	last_tx = <<>>, % Get last TX hash.
	owner = <<>>, % Public key of transaction owner.
	tags = [], % Indexable TX category identifiers.
	target = <<>>, % Address of target of the tx.
	quantity = 0, % Amount of Winston to send.
	data = <<>>, % Data in transaction (if data transaction).
	signature = <<>>, % Transaction signature.
	reward = 0 % Transaction mining reward.
}).

%% @doc Gossip protocol state.
%% Passed to and from the gossip library functions (ar_gossip).
-record(gs_state, {
	peers, % A list of the peers known to this node.
	heard = [], % Hashes of the messages received thus far.
	loss_probability = 0, % Message loss probability for network simulation.
	delay = 0, % Message passing delay for network simulation.
	xfer_speed = undefined % Transfer speed in bytes/s for network simulation.
}).

%% @doc A message intended to be handled by the gossip protocol
%% library (ar_gossip).
-record(gs_msg, {
	hash,
	data
}).

%% @doc A record to describe a known Arweave network service.
-record(service, {
	name,
	host,
	expires
}).

% @doc A record to define HTTP Performance results for a given node.
-record(performance, {
	bytes = 0,
	time = 0,
	transfers = 0,
	timestamp = 0,
	timeout = os:system_time(seconds)
}).

%% @doc A Macro to return number of winstons per given AR.
-define(AR(AR), (?WINSTON_PER_AR * AR)).

%% @doc A Macro to return whether an object is a block.
-define(IS_BLOCK(X), (is_record(X, block))).

%% @doc A Macro to return whether a value is an address.
-define(IS_ADDR(Addr), (is_binary(Addr) and (bit_size(Addr) == ?HASH_SZ))).

%% The messages to be stored inside the genesis block.
-define(GENESIS_BLOCK_MESSAGES, []).