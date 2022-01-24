%%% cse_gtt.erl
%%%---------------------------------------------------------------------
%%% @copyright 2022 SigScale Global Inc.
%%% @end
%%%---------------------------------------------------------------------
%%% @doc Global Title Table.
%%% 	This module implements generic prefix matching tables for digit
%%% 	strings using an {@link //mnesia} backing store.  Prefix matching
%%% 	may be done effeciently because each unique prefix is stored
%%% 	in the table.  A lookup for `"1519"' may be done in up to four
%%%	steps.  First find `"1"' as a key, if the key is not found the
%%% 	prefix does not exist in the table.  If the value for the key
%%% 	is undefined lookup `"15"' and if that key's value is undefined
%%% 	lookup `"151"' This continues until either the key is not found
%%% 	or the value is not undefined.
%%%
%%% 	The example below shows the table contents after an initial entry
%%%	of the form:<br />
%%%	``1> cse_gtt:insert(global_title, "1519240", "Bell Mobility").''
%%%	```
%%%		{gtt, [1], undefined}
%%%		{gtt, [1,5], undefined}
%%%		{gtt, [1,5,1], undefined}
%%%		{gtt, [1,5,1,9], undefined}
%%%		{gtt, [1,5,1,9,2], undefined}
%%%		{gtt, [1,5,1,9,2,4], undefined}
%%%		{gtt, [1,5,1,9,2,4,0], "Bell Mobility"}
%%% 	'''
%%%
%%% 	<strong>Note:</strong> <emp>There is no attempt made to clean the
%%% 	table properly when a prefix is deleted.</emp>
%%%
%%% @todo Implement garbage collection.
%%% @end
%%%
-module(cse_gtt).
-copyright('Copyright (c) 2022 SigScale Global Inc.').

%% export API

%%----------------------------------------------------------------------
%%  The GTT API
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

