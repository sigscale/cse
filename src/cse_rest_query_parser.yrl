Header
"%%% vim: ts=3: "
"%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
"%%% @copyright 2022 SigScale Global Inc."
"%%% @end"
"%%% Licensed under the Apache License, Version 2.0 (the \"License\");"
"%%% you may not use this file except in compliance with the License."
"%%% You may obtain a copy of the License at"
"%%%"
"%%%     http://www.apache.org/licenses/LICENSE-2.0"
"%%%"
"%%% Unless required by applicable law or agreed to in writing, software"
"%%% distributed under the License is distributed on an \"AS IS\" BASIS,"
"%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied."
"%%% See the License for the specific language governing permissions and"
"%%% limitations under the License."
"%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
"%%% @doc This library module implements a parser for JSONPath,"
"%%%  as described in TMF630 REST API Design Guidelines - Part 6,"
"%%% 	in the {@link //cse. cse} application."
"%%%"
"%%% 	This module is generated with {@link //parsetools/yecc. yecc}"
"%%% 	from `{@module}.yrl'."
"%%%"
"%%% @author Vance Shipley <vances@sigscale.org>"
"%%% @reference <a href=\"https://www.tmforum.org/resources/specification/tmf630-rest-api-design-guidelines-4-2-0/\">"
"%%% 	TMF630</a> REST API Design Guidelines - Part 6 JSONPath Extension"
"%%% @reference <a href=\"https://tools.ietf.org/id/draft-goessner-dispatch-jsonpath-00.html\">"
"%%% 	JSONPath</a> XPath for JSON"
"%%%"
"%%%  <h2><a name=\"functions\">Function Details</a></h2>"
"%%%"
"%%%  <h3 class=\"function\"><a name=\"parse-1\">parse/1</a></h3>"
"%%%  <div class=\"spec\">"
"%%%  <p><tt>parse(Tokens) -&gt; Result</tt>"
"%%%  <ul class=\"definitions\">"
"%%%    <li><tt>Tokens = [Token] </tt></li>"
"%%%    <li><tt>Token = {Category, LineNumber, Symbol}"
"%%%        | {Symbol, LineNumber}</tt></li>"
"%%%    <li><tt>Category = word</tt></li>"
"%%%    <li><tt>Symbol = '\"' | '[' | ']' | '{' | '}' | '.' | ','"
"%%%        | Operator</tt></li>"
"%%%    <li><tt>Result = {ok, JSONPath}"
"%%%        | {error, {LineNumber, Module, Message}}</tt></li>"
"%%%    <li><tt>JSONPath = {Root, Steps}</tt></li>"
"%%%    <li><tt>Root = '$'</tt></li>"
"%%%    <li><tt>Steps = [Step]</tt></li>"
"%%%    <li><tt>step = {'.', Children} | {'..', Descendents}</tt></li>"
"%%%    <li><tt>Children = Descendents = Slice | Filter | Script</tt></li>"
"%%%    <li><tt>Slice = {slice, Start, End}</tt></li>"
"%%%    <li><tt>Start = End = integer() | undefined</tt></li>"
"%%%    <li><tt>Filter = {filter, BooleanExpression}</tt></li>"
"%%%    <li><tt>Script = {script, BooleanExpression}</tt></li>"
"%%%    <li><tt>BooleanExpression = {Operator, Operand [,Operand]}</tt></li>"
"%%%    <li><tt>Operator = exact | notexact | lt | lte | gt | gte"
"%%%        | regex | min | max | avg | stddev | len | 'band' | 'bor'</tt></li>"
"%%%    <li><tt>Operaand = Element | Value | BooleanExpression</tt></li>"
"%%%    <li><tt>Element = {'@', Path} | {'$'. Path}</tt></li>"
"%%%    <li><tt>Path = [string()]</tt></li>"
"%%%    <li><tt> Value  string() | number() | boolean()</tt></li>"
"%%%  </ul></p>"
"%%%  </div>"
"%%%  <p>Parse the input <tt>Tokens</tt> according to the grammar"
"%%%  of JSON Path expressions.</p>"
"%%%"
.

Nonterminals param step steps slice start end attributename
		valueexpression valueexpressions filterexpression scriptexpression
		booleanexpression element path value.

Terminals 
		'$' '..' '.' '[' ']' '*' ',' ':' '@' '?' '(' ')'
		string word integer float boolean min max avg stddev len
		exact notexact lt lte gt gte regex negate band bor plus minus.

Rootsymbol param.

Left 100 band bor.
Nonassoc 200 exact notexact lt lte gt gte regex.
Unary 300 minus plus.

param -> '$' steps : {'$', '$2'}.
param -> steps : {'$', '$1'}.
steps -> step : ['$1'].
steps -> step steps : ['$1' | '$2'].
step -> '..' attributename : {'..', ['$2']}.
step -> '.' attributename : {'.', ['$2']}.
step -> attributename : {'.', ['$1']}.
step -> '[' slice ']' : {'.', '$2'}.
step -> '[' valueexpressions ']' : {'.', '$2'}.
valueexpressions -> valueexpression : ['$1'].
valueexpressions -> valueexpression ',' valueexpressions : ['$1' | '$3'].
valueexpression -> attributename : '$1'.
valueexpression -> scriptexpression : '$1'.
valueexpression -> filterexpression : '$1'.
% slice -> start ':' end ':' step.
slice -> start ':' end : {slice, '$1', '$3'}.
slice -> start ':' : {slice, '$1', undefined}.
slice -> ':' end : {slice, undefined, '$2'}.
start -> integer : element(3, '$1').
start -> minus integer : - element(3, '$2').
end -> integer : element(3, '$1').
end -> minus integer : - element(3, '$2').
attributename -> word : element(3, '$1').
attributename -> '*' : '_'.  % wildcard.
scriptexpression -> '(' booleanexpression ')' : {script, '$2'}.
filterexpression -> '?' '(' booleanexpression ')' : {filter, '$3'}.
booleanexpression -> element : '$1'.
booleanexpression -> value : '$1'.
booleanexpression -> scriptexpression : '$1'.
booleanexpression -> booleanexpression exact booleanexpression: {exact, '$1', '$3'}.
booleanexpression -> booleanexpression notexact booleanexpression: {notexact, '$1', '$3'}.
booleanexpression -> booleanexpression lt booleanexpression: {lt, '$1', '$3'}.
booleanexpression -> booleanexpression lte booleanexpression: {lte, '$1', '$3'}.
booleanexpression -> booleanexpression gt booleanexpression: {gt, '$1', '$3'}.
booleanexpression -> booleanexpression gte booleanexpression: {gte, '$1', '$3'}.
booleanexpression -> booleanexpression regex booleanexpression: {regex, '$1', '$3'}.
booleanexpression -> booleanexpression band booleanexpression: {'band', '$1', '$3'}.
booleanexpression -> booleanexpression bor booleanexpression: {'bor', '$1', '$3'}.
booleanexpression -> negate booleanexpression : {negate, '$2'}.
booleanexpression -> booleanexpression '.' min : {min, '$1'}.
booleanexpression -> booleanexpression '.' max : {max, '$1'}.
booleanexpression -> booleanexpression '.' avg : {avg, '$1'}.
booleanexpression -> booleanexpression '.' stddev : {stddev, '$1'}.
booleanexpression -> booleanexpression '.' len : {len, '$1'}.
path -> '.' attributename : ['$2'].
path -> '.' attributename path : ['$2' | '$3'].
element -> '@' path : {'@', '$2'}.
element -> '$' path : {'$', '$2'}.
value -> string : element(3, '$1').
value -> minus integer : - element(3, '$1').
value -> plus integer : element(3, '$1').
value -> integer : element(3, '$1').
value -> minus float : - element(3, '$1').
value -> plus float : element(3, '$1').
value -> float : element(3, '$1').
value -> boolean : list_to_existing_atom(element(3, '$1')).

