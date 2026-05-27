import { LightningElement} from 'lwc';

// social media icons and logo imports
import BCFooter from '@salesforce/resourceUrl/BatonCare_Logo_With_Tagline';

export default class batonCareFooter extends LightningElement {
    // Reference each image inside the ZIP file
    logoUrl = BCFooter;
    currentYear = new Date().getFullYear();
}