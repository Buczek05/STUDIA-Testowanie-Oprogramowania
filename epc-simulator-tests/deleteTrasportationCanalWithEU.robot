*** Settings ***
Documentation    Testy funkcjonalności - usunięcie kanału transportowego z UE.
...              - Możliwe jest usunięcie dedykowanego bearera dla UE
...              - Procedura wymaga podania UE ID oraz bearer ID
...              - Jeśli bearer jest spoza zakresu -> błąd
...              - Jeśli bearer nie jest aktywny -> błąd
...              - Nie można usunąć domyślnego bearera
Library          RequestsLibrary
Library          Collections
Suite Setup      Create Session    epc    ${BASE_URL}
Test Setup       Reset EPC

*** Variables ***
${BASE_URL}               http://localhost:8000
${VALID_UE_ID}            ${80}
${DEDICATED_BEARER}       ${1}
${DEFAULT_BEARER}         ${9}
${OUT_OF_RANGE_BEARER}    ${999}

*** Test Cases ***
T-013 Delete Dedicated Bearer Succeeds
    [Documentation]    Usunięcie dedykowanego bearera (wymaga UE ID i bearer ID).
    [Tags]    delete-bearer    happy-path
    Attach UE ${VALID_UE_ID}
    Add Bearer ${VALID_UE_ID} ${DEDICATED_BEARER}
    Start Traffic ${VALID_UE_ID} ${DEDICATED_BEARER}
    Delete Bearer ${VALID_UE_ID} ${DEDICATED_BEARER}
    Delete Should Succeed ${VALID_UE_ID} ${DEDICATED_BEARER}

T-014 Delete Missing Params Rejected
    [Documentation]    Brak bearer ID w żądaniu -> odrzucenie.
    [Tags]    delete-bearer    error
    Delete Bearer Without ID ${VALID_UE_ID}

T-015 Delete Out Of Range Rejected
    [Documentation]    Bearer spoza zakresu -> błąd.
    [Tags]    delete-bearer    error
    Attach UE ${VALID_UE_ID}
    Delete Bearer ${VALID_UE_ID} ${OUT_OF_RANGE_BEARER}
    Delete Should Be Rejected

T-016 Delete Non-Active Bearer Rejected
    [Documentation]    Próba usunięcia nieaktywnego bearera -> błąd.
    [Tags]    delete-bearer    error
    Attach UE ${VALID_UE_ID}
    Add Bearer ${VALID_UE_ID} ${DEDICATED_BEARER}
    # nie uruchamiamy traffic -> bearer nieaktywny
    Delete Bearer ${VALID_UE_ID} ${DEDICATED_BEARER}
    Delete Should Be Rejected

T-017 Cannot Delete Default Bearer
    [Documentation]    Nie można usunąć domyślnego bearera (ID ${DEFAULT_BEARER}).
    [Tags]    delete-bearer    error    default
    Attach UE ${VALID_UE_ID}
    Delete Bearer ${VALID_UE_ID} ${DEFAULT_BEARER}
    Delete Should Be Rejected

*** Keywords ***
Reset EPC
    [Documentation]    Przywraca symulator do stanu początkowego przed każdym testem.
    POST On Session    epc    /reset

Attach UE ${ue_id}
    [Documentation]    Podłącza UE (helper do przygotowania stanu).
    ${body}=    Create Dictionary    ue_id=${ue_id}
    ${response}=    POST On Session    epc    /ues    json=${body}    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

Add Bearer ${ue_id} ${bearer_id}
    [Documentation]    Dodaje dedykowany bearer do UE.
    ${body}=    Create Dictionary    bearer_id=${bearer_id}
    ${response}=    POST On Session    epc    /ues/${ue_id}/bearers    json=${body}    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

Start Traffic ${ue_id} ${bearer_id}
    [Documentation]    Uruchamia traffic na wskazanym bearerze (ustawia active).
    ${body}=    Create Dictionary    protocol=tcp
    ${response}=    POST On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic    json=${body}    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

Delete Bearer ${ue_id} ${bearer_id}
    [Documentation]    Usuwa bearer podanym UE ID i bearer ID.
    ${response}=    DELETE On Session    epc    /ues/${ue_id}/bearers/${bearer_id}    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

Delete Bearer Without ID ${ue_id}
    [Documentation]    Wysyła DELETE bez podania bearer ID (oczekiwane odrzucenie).
    ${response}=    DELETE On Session    epc    /ues/${ue_id}/bearers    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}
    Should Be True    ${LAST_RESPONSE.status_code} >= 400

Delete Should Succeed ${ue_id} ${bearer_id}
	[Documentation]    Weryfikuje, że ostatnia operacja usunięcia zwróciła sukces.
	Status Should Be	200	${LAST_RESPONSE}
	Should Be Equal As Strings	${LAST_RESPONSE.json()}[status]	bearer_deleted
	Should Be Equal As Integers	${LAST_RESPONSE.json()}[ue_id]	${ue_id}
	Should Be Equal As Integers	${LAST_RESPONSE.json()}[bearer_id]	${bearer_id}

Delete Should Be Rejected
    [Documentation]    Weryfikuje, że ostatnia operacja usunięcia została odrzucona.
    Should Be True    ${LAST_RESPONSE.status_code} >= 400
