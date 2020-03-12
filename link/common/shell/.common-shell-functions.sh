# Reference: https://gist.github.com/lounagen/bdcf3e59122e80bae6da114352d0280c

function _decode_jwt_part(){
   # make sure input is a valid base64 encoded string
   # if input length is not divisible by 4, pad input with =
   local len=$((${#1} % 4))
   local jwt_part="$1"
   if [ $len -eq 2 ]; then jwt_part="$1"'=='
   elif [ $len -eq 3 ]; then jwt_part="$1"'='
   fi
   echo "$jwt_part" | tr '_-' '/+' | base64 --decode | jq .
}

function _select_jwt_part() {
   local token=$1
   local index=$2
   echo -n ${token} | cut -d "." -f ${index}
}

function jwth() {
   # Decode JWT header
   local token=$1
   local header=$(_select_jwt_part ${token} 1)
   _decode_jwt_part ${header}
}

function jwtp() {
   # Decode JWT Payload
   local token=$1
   local payload=$(_select_jwt_part ${token} 2)
   _decode_jwt_part ${payload}
}

function jwt(){
   # Decode JWT header and payload
   # JWT format: header.payload.signature
   local token=$1
   echo "Header: "
   jwth ${token}

   echo "Payload: "
   jwtp ${token}
}
