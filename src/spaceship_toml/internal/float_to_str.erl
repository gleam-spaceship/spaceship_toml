-module(float_to_str).
-export([convert/1]).

convert(F) ->
    lists:flatten(io_lib:format("~p", [F])).
