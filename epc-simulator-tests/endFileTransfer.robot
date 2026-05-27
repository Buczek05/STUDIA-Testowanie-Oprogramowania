*** Settings ***
Documentation    Testy funkcjonalności - zakończenie przesyłania danych (end file transfer).
...              Transfer danych można zakończyć dla poszczególnego bearera w ramach UE lub całkowicie dla wszystkich bearerów.
...              Procedura wymaga podania UE ID oraz opcjonalnie bearer ID.
Library          RequestsLibrary
Library          Collections
Suite Setup      Create Session    epc    ${BASE_URL}
Test Setup       Reset EPC

*** Variables ***
${BASE_URL}           http://localhost:8000
${VALID_UE_ID}        ${50}
${VALID_BEARER_ID}    ${9}

*** Test Cases ***
T-009 End Transfer For Single Bearer Succeeds
	[Documentation]    Zakończenie transferu dla jednego bearera w UE.
	[Tags]    end-transfer    bearer    happy-path
	Attach UE ${VALID_UE_ID}
	End Transfer For Bearer ${VALID_UE_ID} ${VALID_BEARER_ID}
	End Transfer Should Confirm Bearer ${VALID_UE_ID} ${VALID_BEARER_ID}

T-010 End Transfer For All Bearers Succeeds
	[Documentation]    Zakończenie transferu dla wszystkich bearerów danego UE (tylko UE ID).
	[Tags]    end-transfer    all    happy-path
	Attach UE ${VALID_UE_ID}
	End Transfer For All Bearers ${VALID_UE_ID}
	End Transfer Should Confirm All Bearers ${VALID_UE_ID}

T-011 End Transfer Missing UE Is Rejected
	[Documentation]    Procedura wymaga UE ID — brak UE ID powoduje błąd.
	[Tags]    end-transfer    error
	End Transfer Without UE Should Be Rejected

T-012 End Transfer With Invalid Bearer Is Rejected
	[Documentation]    Nieistniejący bearer ID powoduje błąd.
	[Tags]    end-transfer    error
	Attach UE ${VALID_UE_ID}
	End Transfer For Bearer ${VALID_UE_ID} 999
	End Transfer For Bearer Should Be Rejected

*** Keywords ***
Reset EPC
	[Documentation]    Przywraca symulator do stanu początkowego przed każdym testem.
	POST On Session    epc    /reset

Attach UE ${ue_id}
	[Documentation]    Podłącza UE (helper do przygotowania stanu).
	${body}=    Create Dictionary    ue_id=${ue_id}
	${response}=    POST On Session    epc    /ues    json=${body}    expected_status=any
	Set Test Variable    ${LAST_RESPONSE}    ${response}

End Transfer For Bearer ${ue_id} ${bearer_id}
	[Documentation]    Kończy transfer dla podanego bearera (UE + bearer) używając DELETE /ues/{ue_id}/bearers/{bearer_id}/traffic.
	${response}=    DELETE On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic    expected_status=any
	Set Test Variable    ${LAST_RESPONSE}    ${response}
    # Zwraza traffic_stopped nawet gdy nie było aktywnego transferu (Bearer)

End Transfer For All Bearers ${ue_id}
	[Documentation]    Kończy transfer dla wszystkich bearerów UE (tu: usuwa traffic dla domyślnego bearer ID).
	${response}=    DELETE On Session    epc    /ues/${ue_id}/bearers/${VALID_BEARER_ID}/traffic    expected_status=any
	Set Test Variable    ${LAST_RESPONSE}    ${response}

End Transfer Should Confirm Bearer ${ue_id} ${bearer_id}
	[Documentation]    Weryfikuje, że odpowiedź potwierdza zakończenie transferu dla bearera.
	Status Should Be    200    ${LAST_RESPONSE}
	Should Be Equal As Strings    ${LAST_RESPONSE.json()}[status]    traffic_stopped
	Should Be Equal As Integers   ${LAST_RESPONSE.json()}[ue_id]    ${ue_id}
	Should Be Equal As Integers   ${LAST_RESPONSE.json()}[bearer_id]    ${bearer_id}

End Transfer Should Confirm All Bearers ${ue_id}
	[Documentation]    Weryfikuje, że odpowiedź potwierdza zakończenie transferów dla wszystkich bearerów UE (sprawdza, że ostatnia operacja zwróciła traffic_stopped).
	Status Should Be    200    ${LAST_RESPONSE}
	Should Be Equal As Strings    ${LAST_RESPONSE.json()}[status]    traffic_stopped
	Should Be Equal As Integers   ${LAST_RESPONSE.json()}[ue_id]    ${ue_id}

End Transfer For Bearer Should Be Rejected
	[Documentation]    Weryfikuje, że zakończenie transferu zostało odrzucone (status >= 400).
	Should Be True    ${LAST_RESPONSE.status_code} >= 400

End Transfer Without UE Should Be Rejected
	[Documentation]    Wysyła żądanie bez UE ID i oczekuje odrzucenia.
	${response}=    POST On Session    epc    /ues/transfer/end    expected_status=any
	Set Test Variable    ${LAST_RESPONSE}    ${response}
	Should Be True    ${LAST_RESPONSE.status_code} >= 400

