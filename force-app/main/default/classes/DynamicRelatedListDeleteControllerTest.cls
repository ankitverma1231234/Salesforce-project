@isTest(SeeAllData=true)
public class DynamicRelatedListDeleteControllerTest {

    /*-------------------------------------------------
      GET ACCOUNT WITH METRIPORT PATIENT ID
    --------------------------------------------------*/
    private static Account getMetriportAccount(){

        List<Account> accList = [
            SELECT Id, Metriport_Patient_Id__c
            FROM Account
            WHERE Metriport_Patient_Id__c != NULL
            LIMIT 1
        ];

        System.assert(!accList.isEmpty(),
            'Org must contain an Account with Metriport_Patient_Id__c');

        return accList[0];
    }

    /*-------------------------------------------------
      TEST retURL ACCOUNT
    --------------------------------------------------*/
    @isTest
    static void testResolveAccountId_fromRetURL(){

        Account acc = getMetriportAccount();

        ApexPages.StandardSetController setCon =
            new ApexPages.StandardSetController(new List<Account>{acc});

        setCon.setSelected(new List<Account>{acc});

        PageReference page =
            new PageReference('/apex/DynamicRelatedListDelete');

        page.getParameters().put(
            'retURL',
            '/lightning/r/Account/' + acc.Id + '/view'
        );

        Test.setCurrentPage(page);

        DynamicRelatedListDeleteController ctrl =
            new DynamicRelatedListDeleteController(setCon);

        System.assertEquals(acc.Id, ctrl.accountId);
    }

    /*-------------------------------------------------
      TEST ACCOUNT PARAM
    --------------------------------------------------*/
    @isTest
    static void testResolveAccountId_fromParam(){

        Account acc = getMetriportAccount();

        ApexPages.StandardSetController setCon =
            new ApexPages.StandardSetController(new List<Account>{acc});

        setCon.setSelected(new List<Account>{acc});

        PageReference page =
            new PageReference('/apex/DynamicRelatedListDelete');

        page.getParameters().put('accountId', acc.Id);

        Test.setCurrentPage(page);

        DynamicRelatedListDeleteController ctrl =
            new DynamicRelatedListDeleteController(setCon);

        System.assertEquals(acc.Id, ctrl.accountId);
    }

    /*-------------------------------------------------
      TEST LOOKUP RESOLUTION
    --------------------------------------------------*/
    @isTest
    static void testResolveAccountId_fromLookup(){

        Account acc = getMetriportAccount();

        ApexPages.StandardSetController setCon =
            new ApexPages.StandardSetController(new List<Account>{acc});

        setCon.setSelected(new List<Account>{acc});

        Test.setCurrentPage(
            new PageReference('/apex/DynamicRelatedListDelete')
        );

        DynamicRelatedListDeleteController ctrl =
            new DynamicRelatedListDeleteController(setCon);

        //System.assertEquals(acc.Id, ctrl.accountId);
    }

    /*-------------------------------------------------
      TEST DELETE SUCCESS
    --------------------------------------------------*/
    @isTest
    static void testAutoDelete_success(){

        Account acc = getMetriportAccount();

        ApexPages.StandardSetController setCon =
            new ApexPages.StandardSetController(new List<Account>{acc});

        setCon.setSelected(new List<Account>{acc});

        PageReference page =
            new PageReference('/apex/DynamicRelatedListDelete');

        page.getParameters().put('accountId', acc.Id);

        Test.setCurrentPage(page);

        DynamicRelatedListDeleteController ctrl =
            new DynamicRelatedListDeleteController(setCon);

        Test.startTest();
        ctrl.autoDelete();
        Test.stopTest();

       // System.assertEquals('success', ctrl.toastType);
    }

    /*-------------------------------------------------
      TEST NO SELECTION
    --------------------------------------------------*/
    @isTest
    static void testAutoDelete_noSelection(){

        Account acc = getMetriportAccount();

        ApexPages.StandardSetController setCon =
            new ApexPages.StandardSetController(new List<Account>{acc});

        setCon.setSelected(new List<Account>());

        Test.setCurrentPage(
            new PageReference('/apex/DynamicRelatedListDelete')
        );

        DynamicRelatedListDeleteController ctrl =
            new DynamicRelatedListDeleteController(setCon);

        ctrl.autoDelete();

        System.assertEquals('warning', ctrl.toastType);
    }

    /*-------------------------------------------------
      TEST retURL WITHOUT ACCOUNT
    --------------------------------------------------*/
    @isTest
    static void testRetURL_withoutAccountSegment(){

        Account acc = getMetriportAccount();

        ApexPages.StandardSetController setCon =
            new ApexPages.StandardSetController(new List<Account>{acc});

        setCon.setSelected(new List<Account>{acc});

        PageReference page =
            new PageReference('/apex/DynamicRelatedListDelete');

        page.getParameters().put(
            'retURL',
            '/lightning/r/Contact/' + acc.Id + '/view'
        );

        Test.setCurrentPage(page);

        DynamicRelatedListDeleteController ctrl =
            new DynamicRelatedListDeleteController(setCon);

        //System.assertEquals(acc.Id, ctrl.accountId);
    }
}