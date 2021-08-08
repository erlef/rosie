-module(interface_compile).

-export([file/1]).

% -behaviour(gen_server).
% -export([init/1,handle_call/3,handle_cast/2]).

-define(GEN_CODE_DIR, "_generated/").

% start_link() -> gen_server:start_link(?MODULE,[],[]).


file(Filename) -> 
    % Leex generation, compilation and loading
    % {ok, ModuleFile} = leex:file(service_syntax),
    % {ok, ModuleName0} = compile:file(ModuleFile),
    % {module, Scanner} = code:load_file(ModuleName0),

    % Yecc rules
    % {ok, ModuleFile2} = yecc:file(service_parser),
    % {ok, ModuleName2} = compile:file(ModuleFile2),
    % {module, Parser} = code:load_file(ModuleName2),

    
    {InterfaceName,Code} = gen_interface(Filename,service_scanner,service_parser),
    %io:format(Code),  
    ok = file:write_file(?GEN_CODE_DIR++InterfaceName++".erl", Code), 
    {ok, ModuleName,Binary} = compile:file(?GEN_CODE_DIR++InterfaceName++".erl",[binary]),
    {module, Interface} = code:load_binary(ModuleName,InterfaceName++".erl",Binary),
    %io:format("Compiled module: ~p\n",[Interface]),
    %io:format("Calling get_name() -> "++Interface:get_name()++"\n"), 
    %io:format("Calling get_type() -> "++Interface:get_type()++"\n"), 
    {ok,Filename}.
% handle_call(_,_,S) -> {reply,ok,S}.
% handle_cast(_,S) -> {noreply,S}.

gen_interface(Filename,Scanner,Parser) -> 
    {ok,Bin} = file:read_file("demos/shared_interfaces/srv/"++Filename),
    %io:format(Bin),
    % checking the work of the scanner
    case Scanner:string(binary_to_list(Bin)) of
        {ok,Tokens,EndLine} -> 
            %io:format("~p\n",[Tokens]),
            % checking the work of the Yecc
            case Parser:parse(Tokens) of
                {ok,Res} ->% print_parsed_info(Res),
                     generate_interface(Filename,Res);
                Else -> io:format("Parser failed: ~p\n",[Else])
            end;
        ErrorInfo -> io:format("Scanner failed: ~p\n",[ErrorInfo])
    end.


generate_interface(Filename,{Request,Reply}) ->
    [Name,"srv"] = string:split(Filename,"."),
    InterfaceName = file_name_to_interface_name(Name),
    RequestVarNames = lists:map(fun({{type,T},{name,N}}) -> N++"," end, Request),
    ReqInput = string:to_upper(string:trim(RequestVarNames,trailing,",")),
    SerializedRequest = string:trim(lists:map(fun(N) -> " "++N++":64/signed-little," end, string:split(ReqInput, ",",all)),trailing, ","),
    {InterfaceName, "-module("++InterfaceName++").

-export([get_name/0, get_type/0, serialize_request/2, serialize_reply/2, parse_request/1, parse_reply/1]).

% GENERAL
get_name() ->
        \""++InterfaceName++"\".

get_type() ->
        \"example_interfaces::srv::dds_::"++Name++"_"++"\".

% CLIENT
serialize_request(Client_ID,{"++ReqInput++"}) -> 
        <<Client_ID:8/binary, 1:64/little, "++SerializedRequest++">>.


parse_reply(<<Client_ID:8/binary, 1:64/little, R:64/signed-little>>) ->
        {Client_ID, R}.

% SERVER        
serialize_reply(Client_ID,R) -> 
        <<Client_ID:8/binary, 1:64/little, R:64/signed-little>>.

parse_request(<<Client_ID:8/binary, 1:64/little,"++SerializedRequest++">>) ->        
        {Client_ID,{"++ReqInput++"}}.
"}.

file_name_to_interface_name(Name) -> 
    Splitted = re:split(Name,"([A-Z])",[{return,list}]),
    Separated = lists:map(fun (S) -> 
                    case string:lowercase(S) /= S of
                        true -> "_" ++ S;
                        false -> S
                    end
                end, Splitted),
    string:lowercase(string:trim(Separated, leading, "_")).



print_parsed_info({Request,Reply}) ->
    io:format("Request is : ~p\nReply is: ~p\n",[Request,Reply]).