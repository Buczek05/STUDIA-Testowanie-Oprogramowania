*** Settings ***
Documentation    Testy funkcjonalności - podłączenie UE do sieci (attach).
...              - UE może zostać dołączony do sieci (wymaga UE ID)
...              - UE ID spoza zakresu -> błąd
...              - UE już podłączony -> błąd
...              - Podłączony UE automatycznie otrzymuje domyślny bearer ID 9
Library          RequestsLibrary
Library          Collections
Suite Setup      Create Session    epc    ${BASE_URL}
Test Setup       Reset EPC

*** Variables ***
${BASE_URL}              http://localhost:8000
${DEFAULT_BEARER_ID}     ${9}
${VALID_UE_ID}           ${50}
${NOT_VALID_EU_ID}       ${-1}

*** Test Cases ***
Attach UE With Valid ID Succeeds
    [Documentation]    UE o poprawnym ID zostaje podłączony, API potwierdza status.
    [Tags]    attach    happy-path
    ${body}=    Create Dictionary    ue_id=${VALID_UE_ID}
    ${response}=    POST On Session    epc    /ues    json=${body}
    Status Should Be    200    ${response}
    Should Be Equal As Strings     ${response.json()}[status]    attached
    Should Be Equal As Integers    ${response.json()}[ue_id]     ${VALID_UE_ID}

Attached UE Receives Default Bearer 9
    [Documentation]    Po attachu UE ma automatycznie ustanowiony domyślny bearer o ID 9.
    [Tags]    attach    default-bearer
    ${body}=    Create Dictionary    ue_id=${VALID_UE_ID}
    POST On Session    epc    /ues    json=${body}
    ${ue}=    GET On Session    epc    /ues/${VALID_UE_ID}
    Status Should Be    200    ${ue}
    Dictionary Should Contain Key    ${ue.json()}[bearers]    9
    Should Be Equal As Integers      ${ue.json()}[bearers][9][bearer_id]    ${DEFAULT_BEARER_ID}

Attach UE With Out Of Range ID Is Rejected
    [Documentation]    UE ID poza zakresem dopuszczalnych wartości -> błąd (spec: "zostanie wyświetlony błąd").
    [Tags]    attach    validation
    ${body}=    Create Dictionary    ue_id=${NOT_VALID_EU_ID}
    ${response}=    POST On Session    epc    /ues    json=${body}    expected_status=any
    Should Be True    ${response.status_code} >= 400
    ...    UE ID ${NOT_VALID_EU_ID} powinien zostać odrzucony, a API zwróciło ${response.status_code}

Attach Already Attached UE Is Rejected
    [Documentation]    Ponowny attach tego samego UE -> błąd (spec: "UE już podłączony").
    [Tags]    attach    conflict
    ${body}=    Create Dictionary    ue_id=${VALID_UE_ID}
    POST On Session    epc    /ues    json=${body}
    ${response}=    POST On Session    epc    /ues    json=${body}    expected_status=any
    Should Be True    ${response.status_code} >= 400
    ...    Drugi attach powinien zwrócić błąd, a API zwróciło ${response.status_code}
    Should Contain    ${response.text}    already attached

*** Keywords ***
Reset EPC
    [Documentation]    Przywraca symulator do stanu początkowego przed każdym testem.
    POST On Session    epc    /reset

