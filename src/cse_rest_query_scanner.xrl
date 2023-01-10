%%% vim: ts=3: 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2022-2023 SigScale Global Inc.
%%% @end
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @author Vance Shipley <vances@sigscale.org>
%%% @doc This is an input file for leex, the lexical analyzer generator
%%% 	to be used in preprocessing input to
%%% 	{@link //cse/cse_rest_query_parser. cse_rest_query_parser} in the
%%% 	{@link //cse. cse} application.
%%%
%%% @reference <a href="https://www.tmforum.org/resources/specification/tmf630-rest-api-design-guidelines-4-2-0/">
%%% 	TMF630</a> REST API Design Guidelines - Part 6 JSONPath Extension
%%% @reference <a href="https://tools.ietf.org/id/draft-goessner-dispatch-jsonpath-00.html">
%%% 	JSONPath</a> XPath for JSON

Definitions.
DIGIT = [0-9]
NAME = \@?[a-zA-Z][a-zA-Z0-9]*


Rules.
%% Main
\$ : {token, {'$', TokenLine}}.
\.\. : {token, {'..', TokenLine}}.
\. : {token, {'.', TokenLine}}.
\[ : {token, {'[', TokenLine}}.
\] : {token, {']', TokenLine}}.
\* : {token, {'*', TokenLine}}.
\, : {token, {',', TokenLine}}.
\: : {token, {':', TokenLine}}.
\? : {token, {'?', TokenLine}}.
\( : {token, {'(', TokenLine}}.
\) : {token, {')', TokenLine}}.

%% Functions
min\(\) : {token, {min, TokenLine}}.
max\(\) : {token, {max, TokenLine}}.
avg\(\) : {token, {avg, TokenLine}}.
stddev\(\) : {token, {stddev, TokenLine}}.
length\(\) : {token, {len, TokenLine}}.

%% Operators
== : {token, {exact, TokenLine}}.
\!= : {token, {notexact, TokenLine}}.
< : {token, {lt, TokenLine}}.
=< : {token, {lte, TokenLine}}.
> : {token, {gt, TokenLine}}.
>= : {token, {gte, TokenLine}}.
=~ : {token, {regex, TokenLine}}.
\! : {token, {negate, TokenLine}}.
\&\& : {token, {'band', TokenLine}}.
\|\| : {token, {'bor', TokenLine}}.
\+ : {token, {plus, TokenLine}}.
\- : {token, {minus, TokenLine}}.

%% Values
{NAME} : {token, {word, TokenLine, TokenChars}}.
{DIGIT}+\.{DIGIT}+((E|e)(\+|-)?{DIGIT}+)? : {token, {float, TokenLine, list_to_float(TokenChars)}}.
{DIGIT}+ : {token, {integer, TokenLine, list_to_integer(TokenChars)}}.
true : {token, {boolean, TokenLine, 'true'}}.
false : {token, {boolean, TokenLine, 'false'}}.
\@ : {token, {'@', TokenLine}}.
\"[^"]*\" : {token, {string, TokenLine, string:slice(TokenChars, 1, TokenLen - 2)}}.
\'[^']*\' : {token, {string, TokenLine, string:slice(TokenChars, 1, TokenLen - 2)}}.
[\s]+ : skip_token.

Erlang code.
%%% @doc The lexical scanner.
%%%  <h2><a name="functions">Function Details</a></h2>
%%%
%%%  <h3 class="function"><a name="string-1">string/1</a></h3>
%%%  <div class="spec">
%%%  <p><tt>string(String) -&gt; Result</tt>
%%%  <ul class="definitions">
%%%    <li><tt>String = string()</tt></li>
%%%    <li><tt>Result = {ok, Tokens, EndLine} | ErrorInfo</tt></li>
%%%    <li><tt>Token = tuple()</tt></li>
%%%    <li><tt>ErrorLine = integer()</tt></li>
%%%    <li><tt>ErrorInfo = {ErrorLine, module(), error_descriptor()}</tt></li>
%%%  </ul></p>
%%%  </div>
%%%  <p>Scan the input <tt>String</tt> according to JSONPath grammar.
%%%  Create <tt>Tokens</tt> suitable for input to
%%%  {@link //cse/cse_rest_query_parser. cse_rest_query_parser}</p>
%%% @end

