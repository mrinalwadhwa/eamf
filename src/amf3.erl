%%%%===================================================================================================================
%% 
%%  amf3
%%
%%  @author Mrinal Wadhwa < email@mrinalwadhwa.com > [ http://www.mrinalwadhwa.com ]
%%
%%  @doc This module can be used to serialize and deserialize data to/from Action Message Format (AMF) 3, which is a
%%  compact binary format used by Adobe Flash Player to serialize ActionScript object graphs 
%%
%%  @reference <a href="http://bit.ly/amf-spec">AMF 3 Specification</a>
%% 
%%  @end 
%%
%%%%===================================================================================================================

-module(amf3).
-export([decode/1, encode/1]).


%% @type amf3()      =   undefined | null | bool() |
%%                       integer() | float() | binary() | 
%%                       xmldoc() | date() | array() | 
%%                       list() | object() | xml() | bytearray().
%%
%% @type xmldoc()    =   {xmldoc, Document::binary()}.
%% @type date()      =   {date, MilliSeconds::float()}.
%% @type array()     =   [ {binary(),amf3()} | {atom(),amf3()} | amf3()]
%% @type object()    =   {object, Class::binary(), Members::dictionary()}.
%% @type xml()       =   {xml, XML::binary()}.
%% @type bytearray() =   {bytearray, Bytes::binary()}.


%%---------------------------------------
%% @doc Decode AMF 3 encoded binary data
%% @end 
%%---------------------------------------

decode(Data) ->
    {Read, Remaining, _, _, _} = read(Data, dict:new(), dict:new(), dict:new()),
    {Read,Remaining}.
  
%%---------------------------------------
%% @doc Encode data to an AMF 3 encoded 
%%      binary form
%% @end 
%%---------------------------------------

encode(Data) -> 
    {Written, _, _, _} = write(Data, dict:new(), dict:new(), dict:new()),
    Written.


%%%%==========================================================================
%%
%%    Internal       
%%
%%%%==========================================================================

%%---------------------------------------
%%  Markers
%%---------------------------------------

-define(UNDEFINED, 16#00).
-define(NULL,      16#01).
-define(FALSE,     16#02).
-define(TRUE,      16#03).
-define(INTEGER,   16#04).
-define(DOUBLE,    16#05).
-define(STRING,    16#06).
-define(XMLDOC,    16#07).
-define(DATE,      16#08).
-define(ARRAY,     16#09).
-define(OBJECT,    16#0A).
-define(XML,       16#0B).
-define(BYTEARRAY, 16#0C).

%%---------------------------------------
%%  Read 
%%---------------------------------------

read(<<?UNDEFINED, Remaining/binary>>, Strings, Objects, Traits) -> {undefined, Remaining, Strings, Objects, Traits};
read(<<?NULL, Remaining/binary>>, Strings, Objects, Traits) -> {null, Remaining, Strings, Objects, Traits};
read(<<?FALSE, Remaining/binary>>, Strings, Objects, Traits) -> {false, Remaining, Strings, Objects, Traits};
read(<<?TRUE, Remaining/binary>>, Strings, Objects, Traits) -> {true, Remaining, Strings, Objects, Traits};


read(<<?INTEGER, Data/binary>>, Strings, Objects, Traits) ->
    {Unsigned, Remaining} = read_uint29(Data),
    case Unsigned > 268435455 of
      true  -> Signed = Unsigned - 536870912,
               {Signed, Remaining, Strings, Objects, Traits};
      false -> Signed = Unsigned,
               {Signed, Remaining,Strings, Objects, Traits}
    end;


read(<<?DOUBLE, Data:64/float, Remaining/binary>>, Strings, Objects, Traits) -> 
    {Data, Remaining, Strings, Objects, Traits};
read(<<?DOUBLE, 16#7F,16#F0,16#00,16#00,16#00,16#00,16#00,16#00, Remaining/binary>>, Strings, Objects, Traits) -> 
    {infinity, Remaining, Strings, Objects, Traits};
read(<<?DOUBLE, 16#FF,16#F0,16#00,16#00,16#00,16#00,16#00,16#00, Remaining/binary>>, Strings, Objects, Traits) -> 
    {'-infinity', Remaining, Strings, Objects, Traits};
read(<<?DOUBLE, 16#FF,16#F8,16#00,16#00,16#00,16#00,16#00,16#00, Remaining/binary>>, Strings, Objects, Traits) -> 
    {nan, Remaining, Strings, Objects, Traits};


read(<<?STRING, Data/binary>>, Strings, Objects, Traits) -> 
    {String,Remaining,S1} = read_string(Data,Strings),
    {String, Remaining, S1, Objects, Traits}; 


read(<<?XMLDOC, Data/binary>>, Strings, Objects, Traits) -> read_as_obj(Data, xmldoc, Strings, Objects, Traits);
read(<<?XML, Data/binary >>, Strings, Objects, Traits) -> read_as_obj(Data, xml, Strings, Objects, Traits);
read(<<?BYTEARRAY, Data/binary >>, Strings, Objects, Traits) -> read_as_obj(Data, bytearray, Strings, Objects, Traits);
read(<<?DATE, Data/binary>>, Strings, Objects, Traits) -> read_as_obj(Data, date, Strings, Objects, Traits);
read(<<?ARRAY, Data/binary >>, Strings, Objects, Traits) -> read_as_obj(Data, array, Strings, Objects, Traits);
read(<<?OBJECT, Data/binary >>, Strings, Objects, Traits) ->read_as_obj(Data, object, Strings, Objects, Traits).


read_uint29(<<0:1, A:7, Remaining/binary>>) -> {A, Remaining};
read_uint29(<<1:1, A:7, 0:1, B:7, Remaining/binary>>) -> {((A bsl 7) bor B),Remaining};
read_uint29(<<1:1, A:7, 1:1, B:7, 0:1, C:7, Remaining/binary>>) -> {((A bsl 14) bor (B bsl 7) bor C), Remaining};  
read_uint29(<<1:1, A:7, 1:1, B:7, 1:1, C:7, D:8, Remaining/binary>>) -> 
    {((A bsl 22) bor (B bsl 15) bor (C bsl 8) bor D), Remaining}.


read_as_obj(Data, Type, Strings, Objects, Traits) ->
    {Header, R} = read_uint29(Data),
    N = Header bsr 1,
    case Header band 1 =:= 0 of
      true  ->  {find(N, Objects), R, Strings, Objects, Traits};
      false ->  Key = dict:size(Objects),
                O = dict:store(Key, place_holder, Objects),
                {Object,Remaining,S,O1,T} = read_as_obj_helper(Type, N, R, Strings, O, Traits),
                O2 = dict:store(Key, Object, O1), 
                {Object, Remaining, S, O2, T}
    end.


read_as_obj_helper(date, _N, Data, Strings, Objects, Traits) ->
    {Milliseconds, R, S, O, T} = read(<<?DOUBLE, Data/binary>>, Strings, Objects, Traits),
    {{date, Milliseconds}, R, S, O, T};


read_as_obj_helper(array, N, Data, Strings, Objects, Traits) ->
    {Associative, R, S, O, T} = read_associative_array(Data, [], Strings, Objects , Traits),
    {Dense, R1, S1, O1, T1} = read_dense_array(N, [], R, S, O, T),
    AssocSize = length(Associative),
    DenseSize = length(Dense),
    if
      AssocSize > 0, DenseSize == 0  -> Arr = Associative;
      AssocSize == 0, DenseSize > 0  -> Arr = Dense;
      AssocSize > 0, DenseSize > 0 -> Arr = Associative ++ Dense;
      AssocSize == 0, DenseSize == 0 -> Arr = []
    end,
    {Arr,R1, S1, O1, T1};


read_as_obj_helper(object, N, Data, Strings, Objects, Traits) ->
    {{ClassName,IsDynamic,IsExternalizable,_,Properties}, R, S, O, T} = read_traits(N, Data, Strings, Objects, Traits),
    case IsExternalizable of
      true  -> {externalizable, R, S, O, T}; %% @todo
      false -> {SealedPD, R1, S1, O1, T1} = read_property_values(Properties, R ,dict:new(), S, O, T),
               case  IsDynamic of
                 false -> {Object, R3, S3, O3, T3} = {{object, ClassName, SealedPD}, R1, S1, O1, T1};
                 true  -> {PD, R2, S2, O2, T2} = read_dynamic_properties(R1, SealedPD, S1, O1, T1), 
                          {Object, R3, S3, O3, T3} = {{object, ClassName, PD}, R2, S2, O2, T2}
               end, 
               {Object, R3, S3, O3, T3}
    end;


read_as_obj_helper(Type, N, Data, Strings, Objects, Traits) ->
    <<Bin:N/binary, Remaining/binary>> = Data,
    {{Type,Bin},Remaining,Strings,Objects,Traits}.


read_associative_array(Data, Array, Strings, Objects, Traits) ->
    {Name, R, S, O, T} = read(<<?STRING,Data/binary>>, Strings, Objects, Traits),
    case Name of
       <<>> -> {lists:reverse(Array), R, S, O, T}; 
          N -> {Value, R2, S2, O2, T2} = read(R, S, O, T),
               A = [{list_to_atom(binary_to_list(N)), Value} | Array], 
               read_associative_array( R2, A, S2, O2, T2)
    end.


read_dense_array(0, List, Data, Strings, Objects, Traits) -> {lists:reverse(List), Data, Strings, Objects, Traits};
read_dense_array(Length, List, Data, Strings, Objects, Traits) ->
    {Item, R, S, O, T} = read(Data, Strings, Objects, Traits),
    read_dense_array(Length-1, [Item|List], R, S, O, T).  


read_dynamic_properties(Data, Dictionary, Strings, Objects, Traits) ->
    {Property, R, S1} = read_string(Data, Strings),
    case Property of
      <<>> -> {Dictionary, R, S1, Objects, Traits};
         _ -> {Value, R1, S2, O1, T1} = read(R, S1,Objects,Traits),
              PropertyAtom = list_to_atom(binary_to_list(Property)),
              PropertyDictionary = dict:store(PropertyAtom,Value, Dictionary),
              read_dynamic_properties(R1, PropertyDictionary, S2, O1, T1)
    end.          


read_property_names(0, Properties,Data,Strings) -> {lists:reverse(Properties), Data, Strings};
read_property_names(Count,Properties,Data,Strings) ->
  {Property, R, S1} = read_string(Data, Strings),
  PropertyAtom = list_to_atom(binary_to_list(Property)),
  read_property_names(Count-1, [PropertyAtom|Properties], R, S1).


read_property_values([], Data, PropertyDictionary, Strings, Objects, Traits) -> 
    {PropertyDictionary, Data, Strings, Objects, Traits};
read_property_values([Property|Tail], Data, Dictionary, Strings, Objects, Traits) ->
        {Value, R, S, O, T} = read(Data, Strings, Objects, Traits),
        PropertyDictionary = dict:store(Property, Value, Dictionary),
        read_property_values( Tail, R, PropertyDictionary, S, O, T).


read_traits(Header, Data, Strings, Objects, Traits) ->
    case Header band 1 =:= 0 of
      true  -> Trait = find(Header bsr 1, Traits),
               {Trait, Data, Strings, Objects, Traits}; 
      false -> IsExternalizable = Header band 2#10 =:= 2#10,
               IsDynamic = Header band 2#100 =:= 2#100,
               Count = Header bsr 3,
               {ClassName, R, S1} = read_string(Data, Strings),
               {Properties, R1, S2} = read_property_names(Count, [], R, S1),
               Trait = {ClassName,IsDynamic,IsExternalizable,Count,Properties},
               T1 = dict:store(dict:size(Traits), Trait, Traits),
               {Trait, R1, S2, Objects, T1}
    end.          


read_string(Data,Strings) -> 
    {Header, R} = read_uint29(Data),
    N = Header bsr 1,
    case Header band 1 =:= 0 of
      true  ->  {find(N, Strings), R, Strings};
      false ->  <<String:N/binary, Remaining/binary>>  = R,
                case String of
                  <<>> -> {String, Remaining, Strings};
                     _ -> Strings1 = dict:store(dict:size(Strings), String, Strings),                       
                          {String, Remaining, Strings1}
                end         
    end.
    

%%---------------------------------------
%%  Write 
%%---------------------------------------

write(undefined, Strings, Objects, Traits) -> {<<?UNDEFINED>>, Strings, Objects, Traits}; 
write(null, Strings, Objects, Traits) ->  {<<?NULL>>, Strings, Objects, Traits}; 
write(false, Strings, Objects, Traits) -> {<<?FALSE>>, Strings, Objects, Traits};   
write(true, Strings, Objects, Traits) -> {<<?TRUE>>, Strings, Objects, Traits};


write(Integer, Strings, Objects, Traits) when is_integer(Integer), Integer >= -268435456, Integer < 0 -> 
    I = write_uint29(536870912 + Integer),
    {<<?INTEGER, I/binary>>, Strings, Objects, Traits};
write(Integer, Strings, Objects, Traits) when is_integer(Integer), Integer =< 268435455, Integer >= 0 -> 
    I = write_uint29(Integer),
    {<<?INTEGER, I/binary>>, Strings, Objects, Traits};
write(Integer, Strings, Objects, Traits) when is_integer(Integer) ->
    Float = math:pow(Integer,1),
    write(Float, Strings, Objects, Traits);    


write(Double, Strings, Objects, Traits) when is_float(Double) -> 
  {<<?DOUBLE, Double/float>>, Strings, Objects, Traits};
write(infinity, Strings, Objects, Traits) -> 
  {<<?DOUBLE,16#7F,16#F0,16#00,16#00,16#00,16#00,16#00,16#00>>, Strings, Objects, Traits};
write('-infinity', Strings, Objects, Traits) -> 
  {<<?DOUBLE,16#FF,16#F0,16#00,16#00,16#00,16#00,16#00,16#00>>, Strings, Objects, Traits};
write(nan, Strings, Objects, Traits) -> 
  {<<?DOUBLE,16#FF,16#F8,16#00,16#00,16#00,16#00,16#00,16#00>>, Strings, Objects, Traits};


write(Atom, Strings, Objects, Traits) when is_atom(Atom) -> 
  write(list_to_binary(atom_to_list(Atom)), Strings, Objects, Traits);
write(String, Strings, Objects, Traits) when is_binary(String) -> 
  {Binary, Strings1} = write_string(?STRING,String,Strings),
  {Binary, Strings1, Objects, Traits};


write({xmldoc, XML}, Strings, Objects, Traits) when is_binary(XML) -> 
  {Binary, Strings1} = write_string(?XMLDOC,XML,Strings),
  {Binary, Strings1, Objects, Traits};


write({date, MilliSeconds}, Strings, Objects, Traits) ->
  {<<?DATE, 16#01, MilliSeconds/float>>, Strings, Objects, Traits};


write({object, ClassName, Members}, Strings, Objects, Traits) -> a;


write({xml, XML}, Strings, Objects, Traits) when is_binary(XML) -> 
  {Binary, Strings1} = write_string(?XML,XML,Strings),
  {Binary, Strings1, Objects, Traits};


write({bytearray, ByteArray}, Strings, Objects, Traits) when is_binary(ByteArray) -> 
    Length = write_uint29(size(ByteArray) bsl 1 bor 1),
    Binary = list_to_binary([?BYTEARRAY,Length,ByteArray]),
    {Binary, Strings, Objects, Traits};


write(List, Strings, Objects, Traits) 
  when is_list(List) ->
    F = fun({K,_V}) when is_binary(K); is_atom(K) -> true;
           (_V) -> false
        end,
    {Associative, Dense} = lists:partition(F,List),
    Length = write_uint29(length(Dense) bsl 1 bor 1),
    {Written,S,O,T} = write_associative_array(Associative,[?ARRAY,Length],Strings, Objects, Traits),
    {Output,S1,O1,T1} = write_dense_array(Dense, Written, S, O, T),
    {list_to_binary(Output),S1,O1,T1}.


write_uint29(Unsigned) when Unsigned >= 16#00000000, Unsigned =< 16#0000007F -> <<Unsigned>>;
write_uint29(Unsigned) when Unsigned >= 16#00000080, Unsigned =< 16#00003FFF ->
  <<((Unsigned bsr 7) bor 16#80), (Unsigned band 16#7F)>>;
write_uint29(Unsigned) when Unsigned >= 16#00004000, Unsigned =< 16#001FFFFF ->
  <<((Unsigned bsr 14) bor 16#80),((Unsigned bsr 7) bor 16#80),(Unsigned band 16#7F)>>;
write_uint29(Unsigned) when Unsigned >= 16#00200000, Unsigned =< 16#1FFFFFFF ->
    <<((Unsigned bsr 22) bor 16#80),((Unsigned bsr 15) bor 16#80),((Unsigned bsr 8) bor 16#80),(Unsigned band 16#FF)>>.


write_dense_array([], Output, Strings, Objects, Traits) -> {Output, Strings, Objects, Traits};
write_dense_array([H|Remaining], Output, Strings, Objects, Traits) -> 
  {JustWritten,S,O,T} = write(H, Strings, Objects, Traits),
  EverythingWritten = [Output,JustWritten],
  write_dense_array(Remaining, EverythingWritten, S, O, T). 


write_associative_array([], Output, Strings, Objects, Traits) -> 
  {lists:flatten([Output,16#01]), Strings, Objects, Traits}; 
write_associative_array([H|Remaining], Output, Strings, Objects, Traits) -> 
  {Key, Value} = H,
  {<<16#06,K/binary>>,S,O,T} = write(Key, Strings, Objects, Traits),    
  {V,S1,O1,T1} = write(Value, S, O, T),
  EverythingWritten = [Output, K, V],
  write_associative_array(Remaining, EverythingWritten, S1, O1, T1).


write_string(Marker, String, Strings) ->
  case dict:find(String, Strings) of
    {ok,Index} -> Strings1 = Strings,
                  Header = write_uint29(Index bsl 1),
                  Binary = list_to_binary([Marker,Header]);
        error  -> Index = dict:size(Strings),
                  Strings1 = dict:store(String, Index, Strings),
                  Header = write_uint29(size(String) bsl 1 bor 1),
                  Binary = list_to_binary([Marker,Header,String])
  end,
  {Binary, Strings1}.


find(Reference, Dictionary) ->
  case dict:find(Reference, Dictionary) of
    {ok, Value} -> Value;
              _ -> throw({error,{reference_not_found,Reference,dict:to_list(Dictionary)}})
  end.